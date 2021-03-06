#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/poll.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/videodev2.h>

#include "misc.h"

int BUFFERS_REQUESTED = 10;

typedef struct mmap_buffer {
  void *start;
  size_t length;
} mmap_buffer;

typedef struct v4l2_reader {
  int fd;
  int mmap_buffer_count;
  mmap_buffer *mmap_buffers;
} v4l2_reader;

typedef struct v4l2_buffer v4l2_buffer;
typedef struct v4l2_format v4l2_format;
typedef struct v4l2_streamparm v4l2_streamparm;
typedef struct v4l2_requestbuffers v4l2_requestbuffers;
typedef struct pollfd pollfd;

inline void prep (v4l2_buffer *buffer) {
  memset (buffer, 0, sizeof *buffer);
  buffer->type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  buffer->memory = V4L2_MEMORY_MMAP;
}

void v4l2_reader_delete (v4l2_reader *v) {
  int i;
  
  if (!v) return;

  if (v->mmap_buffers) {
    for (i = 0; i < v->mmap_buffer_count; i++) {
      munmap (v->mmap_buffers[i].start, v->mmap_buffers[i].length);
    }
    free (v->mmap_buffers);
  }
  close (v->fd);
  free (v);
}

v4l2_reader* v4l2_reader_new (void) {
  v4l2_reader *v;

  v = malloc (sizeof (v4l2_reader));
  if (v) {
    v->fd = -1;
    v->mmap_buffer_count = 0;
    v->mmap_buffers = NULL;
  }
  return v;
}

int v4l2_reader_open (v4l2_reader *v, char *devicename, unsigned int w, unsigned int h) {
  v4l2_format format;
  
  v->fd = open (devicename, O_RDWR);

  /* set pixel format, width, height, fps */
  /* try setting format and size */
  memset (&format, 0x00, sizeof format);
  format.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (0 > ioctl (v->fd, VIDIOC_G_FMT, &format)) {
    log_err ("get video format info");
    return 0;
  }
  
  if (format.type != V4L2_BUF_TYPE_VIDEO_CAPTURE ||
      format.fmt.pix.pixelformat != V4L2_PIX_FMT_YUYV ||
      format.fmt.pix.width != w ||
      format.fmt.pix.height != h) {
    format.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    format.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
    format.fmt.pix.field = 1;
    format.fmt.pix.width = w;
    format.fmt.pix.height = h;

    if (0 > ioctl (v->fd, VIDIOC_S_FMT, &format)) {
      log_err ("setting pixel format and frame dimensions");
      return 0;
    }
  }

  memset (&format, 0x00, sizeof format);
  format.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  ioctl (v->fd, VIDIOC_G_FMT, &format);

  // cap the fps at 20 (for demo purposes).
  v4l2_streamparm stream;
  memset (&stream, 0, sizeof stream);
  stream.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (0 > ioctl (v->fd, VIDIOC_G_PARM, &stream)) {
    log_err ("setting framerate");
  } else {
    stream.parm.capture.timeperframe.numerator = 1;
    stream.parm.capture.timeperframe.denominator = 20;
    ioctl (v->fd, VIDIOC_S_PARM, &stream);
  }
  
  return 1;
}

void v4l2_reader_get_params (v4l2_reader *v,
                             /* output */
                             unsigned int *frame_width,
                             unsigned int *frame_height,
                             unsigned int *fps_num,
                             unsigned int *fps_denom,
                             unsigned int *buffer_count) {
  v4l2_streamparm stream;
  v4l2_format format;

  *buffer_count = v->mmap_buffer_count;
  
  memset (&stream, 0, sizeof stream);
  stream.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  memset (&format, 0, sizeof format);
  format.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;

  if (0 > ioctl (v->fd, VIDIOC_G_PARM, &stream)) {
    log_err ("VIDIOC_G_PARM");
     *fps_num = 0;
     *fps_denom = 0;
  } else {
    *fps_num = stream.parm.capture.timeperframe.numerator;
    *fps_denom = stream.parm.capture.timeperframe.denominator;
  }
  
  if (0 > ioctl (v->fd, VIDIOC_G_FMT, &format)) {
    log_err ("VIDIOC_G_FMT");
     *frame_width = 0;
     *frame_height = 0;
  } else {
    *frame_width = format.fmt.pix.width;
    *frame_height = format.fmt.pix.height;
  }
}

int v4l2_reader_make_buffers (v4l2_reader *v) {
  unsigned int i;
  v4l2_requestbuffers reqbuf;
  v4l2_buffer buffer;
      
  memset (&reqbuf, 0, sizeof reqbuf);
  reqbuf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  reqbuf.count = BUFFERS_REQUESTED;
  reqbuf.memory = V4L2_MEMORY_MMAP;

  if (ioctl (v->fd, VIDIOC_REQBUFS, &reqbuf) < 0) {
    log_err ("requesting mmap buffers");
    return 0;
  }

  v->mmap_buffers = calloc (reqbuf.count, sizeof (mmap_buffer));
  v->mmap_buffer_count = reqbuf.count;

  for (i = 0; i < reqbuf.count; i++) {  
    prep (&buffer);
    buffer.index = i;
    
    if (-1 == ioctl (v->fd, VIDIOC_QUERYBUF, &buffer)) {
      log_err ("VIDIOC_QUERYBUF");
      return 0;
    }
    
    v->mmap_buffers[i].length = buffer.length;
    v->mmap_buffers[i].start = mmap (NULL, buffer.length,
                                     PROT_READ | PROT_WRITE,
                                     MAP_SHARED, v->fd, buffer.m.offset);
    if (MAP_FAILED == v->mmap_buffers[i].start) {
      log_err ("starting buffer mapping");
      return 0;
    }
  }

  return 1;
}

int v4l2_reader_start_stream (v4l2_reader *v) {
  int i = V4L2_BUF_TYPE_VIDEO_CAPTURE;

  if (0 > ioctl (v->fd, VIDIOC_STREAMON, &i)) {
    log_err ("starting streaming on device");
    return 0;
  } else {
    return 1;
  }
}

int v4l2_reader_enqueue_buffer (v4l2_reader *v, int index) {
  v4l2_buffer buffer;

  prep (&buffer);
  buffer.index = index;
  
  if (0 > ioctl (v->fd, VIDIOC_QBUF, &buffer)) {
    log_err ("queuing buffer");
    return 0;
  } else {
    return 1;
  }
}

int v4l2_reader_dosetup (v4l2_reader *v, char *devicename, unsigned int w, unsigned int h) {
  int res, i;

  res = v4l2_reader_open (v,devicename,w,h) &&
      v4l2_reader_make_buffers (v) &&
      v4l2_reader_start_stream (v);

  if (!res) return 0;

  for (i = 0; i < v->mmap_buffer_count; i++) {
    res &= v4l2_reader_enqueue_buffer (v, i);
  }

  return res;
}

v4l2_reader* v4l2_reader_setup (char *devicename, int w, int h) {

  v4l2_reader *v = v4l2_reader_new ();
  
  if (!v) {
    log_err ("couldn't create reader");
    return NULL;
  }
  
  if (!(v4l2_reader_dosetup (v,devicename,w,h))) {
    log_err ("reader setup");
    v4l2_reader_delete (v);
    return NULL;
  }
  
  return v;
}
 

int v4l2_reader_is_ready (v4l2_reader *v) {
  pollfd pfd;

  pfd.fd = v->fd;
  pfd.events = POLLIN;
  
  if (poll (&pfd, 1, 0) > 0) {
    return pfd.revents & POLLIN;
  } else {
    return 0;
  }
}

int v4l2_reader_dequeue_buffer (v4l2_reader *v,
                                v4l2_buffer *buffer) {
  prep (buffer);
  
  if (ioctl (v->fd, VIDIOC_DQBUF, buffer) < 0) {
    log_err ("dequeuing buffer");
    return 0;
  } else {
    return 1;
  }
}

unsigned char * v4l2_reader_get_frame (v4l2_reader *v,
                                       /* output */
                                       int *size,
                                       int *framenum,
                                       int *index) {
  v4l2_buffer buffer;
  
  if (v4l2_reader_dequeue_buffer (v, &buffer)) {
      *size = buffer.bytesused;
      *framenum = buffer.sequence;
      *index = buffer.index;
      return v->mmap_buffers[buffer.index].start;
  }
  
  log_err ("couldn't dequeue anything");
  *size = 0;
  *framenum = -1;
  *index = -1;
  return NULL; 
}

int main (void) { return 0; }
