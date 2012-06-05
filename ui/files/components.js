var chart;
var pMenuBar;
var websocket;

require([ "dijit/form/Button", "dijit/layout/BorderContainer",
		"dijit/layout/ContentPane", "dijit/form/NumberTextBox",
		"dijit/DropDownMenu", "dijit/MenuItem", "dijit/form/DropDownButton",
		"dijit/MenuBar", "dijit/Menu", "dijit/MenuBarItem",
		"dijit/PopupMenuBarItem", "dojo/data/ItemFileReadStore",
		"dijit/form/Select", "dojo/domReady!" ], function(Button,
		BorderContainer, ContentPane, NumberTextBox, DropDownMenu, MenuItem,
		DropDownButton, MenuBar, Menu, MenuBarItem, PopupMenuBarItem,
		ItemFileReadStore, Select) {
	pMenuBar = new MenuBar({});
	var pSubMenu = new DropDownMenu({});
	/*
	 * pSubMenu.addChild(new MenuItem({ label:"File item #1" }));
	 * pSubMenu.addChild(new MenuItem({ label:"File item #2" }));
	 * pMenuBar.addChild(new PopupMenuBarItem({ label:"File", popup:pSubMenu
	 * }));
	 * 
	 * var pSubMenu2 = new DropDownMenu({}); pSubMenu2.addChild(new MenuItem({
	 * label:"Edit item #1" })); pSubMenu2.addChild(new MenuItem({ label:"Edit
	 * item #2" })); pMenuBar.addChild(new PopupMenuBarItem({ label:"Edit",
	 * popup:pSubMenu2 }));
	 */

	pMenuBar.placeAt("wrapper");
	pMenuBar.startup();
	// webGLStart();

	websocket = new WebSocket("ws://localhost:8080/" + window.location.search);

	websocket.onopen = function(event) {
		alert('telling the server we are ready');
		websocket.send(JSON.stringify({go : ""}));
	}
	
	websocket.onmessage = function(event) {
		console.log(msg);
		var msg = JSON.parse(event.data);
		switch (msg.action) {
		case "newitem":
			switch (msg.item) {
			case "button":
				var response = AddButton(msg.id, msg.label, msg.callback);
				var responsemsg = {
					id : response
				};
				websocket.send(JSON.stringify(responsemsg));
				break;
			case "menu":
				var response = AddPopupMenu(msg.id, msg.label);
				var responsemsg = {
					id : response
				};
				websocket.send(JSON.stringify(responsemsg));
				break;
			case "menuitem":
				var response = AddMenuItem(msg.id, msg.label, msg.menuid,
						msg.callback);
				var responsemsg = {
					id : response
				};
				websocket.send(JSON.stringify(responsemsg));
				break;
			case "canvas":
				var response = AddCanvas(msg.id, msg.label, msg.width,
						msg.height);
				var responsemsg = {
					id : response
				};
				websocket.send(JSON.stringify(responsemsg));
				break;
			case "dropdown":
				var response = AddSelectBox(msg.id, msg.label, msg.data);
				var responsemsg = {
					id : response
				};
				websocket.send(JSON.stringify(responsemsg));
				break;
			}
			break;
		case "updateitem":
			switch (msg.item) {
			case "canvas":
				alert('updating');
				updateCanvas(msg.id, msg.data);
				break;
			}
		}
	}
});

function AddButton(id, label, passedFunction) {
	var row = document.getElementById('newbutton');
	var column = document.createElement('td');
	var button = document.createElement('button');
	button.id = id;
	column.appendChild(button);
	row.appendChild(column);

	document.getElementById(id).value = "New Button Text";

	var widg = new dijit.form.Button({
		label : (label),
		onClick : function() {
			// Do something:
			eval(passedFunction)
		}
	}, (id)); // options,elementID

	// widg.refresh();
	document.getElementById('newbutton').id = '';
	var newbutton = document.createElement('div');
	newbutton.id = 'newbutton';
	document.body.insertBefore(newbutton, null);
	// dojo.parser.parse(dojo.byId(id));
	return button.id;
}

function ReturnOne() {
	var num = new Number(1);
	return num;
}

function AddPopupMenu(id, label) {
	var menu = new dijit.DropDownMenu({
		id : id
	});
	pMenuBar.addChild(new dijit.PopupMenuBarItem({
		label : label,
		popup : menu
	}));
}

function AddMenuItem(id, label, menuid, passedFunction) {
	var menu = dijit.byId(menuid);
	menu.addChild(new dijit.MenuItem({
		id : id,
		label : label,
		onClick : function() {
			eval(passedFunction)
		}
	}));
}

function AddChart(id) {
	var chart;
	$(document)
			.ready(
					function() {
						chart = new Highcharts.Chart(
								{
									chart : {
										renderTo : 'chart',
										type : 'line',
										margin : [ 70, 50, 60, 80 ],
										events : {
											click : function(e) {
												// find the clicked values and
												// the series
												var x = e.xAxis[0].value, y = e.yAxis[0].value, series = this.series[0];

												// Add it
												series.addPoint([ x, y ]);

											}
										}
									},
									title : {
										text : 'Add Data Here'
									},
									subtitle : {
										text : 'Click the plot area to add a point. Click a point to remove it.'
									},
									xAxis : {
										minPadding : 0.2,
										maxPadding : 0.2,
										maxZoom : 60
									},
									yAxis : {
										title : {
											text : 'Value'
										},
										minPadding : 0.2,
										maxPadding : 0.2,
										maxZoom : 60,
										plotLines : [ {
											value : 0,
											width : 1,
											color : '#808080'
										} ]
									},
									legend : {
										enabled : false
									},
									exporting : {
										enabled : false
									},
									plotOptions : {
										series : {
											lineWidth : 1,
											point : {
												events : {
													'click' : function() {
														if (this.series.data.length > 1)
															this.remove();
													}
												}
											}
										}
									},
									series : [ {
										data : [ [ 20, 20 ], [ 80, 80 ] ]
									} ]
								});
					});

}

function randomInt(range) {
	return Math.floor(Math.random() * range);
}

/*
 * window.setInterval(function () { if (window.document.title == 'hi') {
 * window.document.title='hello'; } else { window.document.title = 'hi'; } },
 * 1000);
 */

function AddSelectBox(id, label, datajsonfile) {
	var dataStore = new dojo.data.ItemFileReadStore({
		url : datajsonfile
	});
	// create Select widget, populating its options from the store
	var select = new dijit.form.Select({
		// id: id,
		name : id,
		store : dataStore,
		maxHeight : -1
	// tells _HasDropDown to fit menu within viewport
	}, "select");
	select.startup();
}

function setRectangle(gl, x, y, width, height) {
	var x1 = x;
	var x2 = x + width;
	var y1 = y;
	var y2 = y + height;
	gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([ x1, y1, x2, y1, x1, y2,
			x1, y2, x2, y1, x2, y2 ]), gl.STATIC_DRAW);
};

var canvases = {}

function AddCanvas(id, width, height) {
	c = make_new_canvas(id, width, height, 1.0);
	canvases[c.id] = c;
	return c.id;
}

function updateCanvas(id, data) {
	var canvas = document.getElementById(canvases[id].id);
	var w = canvas.width / canvases[id].scale;
	var h = canvas.height / canvases[id].scale;
	// hack for now, will be replaced by actual data
	var data = new Uint8Array(new ArrayBuffer(w * h * 4));
	for (i = 0; i < w * h * 4; data[i++] = randomInt(256))
		;

	canvases[id].update(data);
}

function make_new_canvas(id, w, h, scale) {

	var my_c = {};

	var going = false;
	var canvasloc = document.getElementById('canvasloc');
	var canvas = document.createElement('canvas');
	canvas.id = id;
	canvas.width = w * scale;
	canvas.height = h * scale;
	canvasloc.appendChild(canvas);

	var arr = new ArrayBuffer(w * h * 4);
	var view = new Uint8Array(arr);
	// initial setup of texture data
	// !!! IMPORTANT !!! modify 'view', NOT 'arr'
	for (i = 0; i < arr.length; view[i++] = randomInt(256))
		;

	var gl;
	try {
		gl = canvas.getContext("experimental-webgl");
		gl.viewport(0, 0, canvas.width, canvas.height);
	} catch (e) {
		alert(e);
	}
	if (!gl) {
		alert("Could not initialise WebGL");
		return my_c;
	}

	vertexShader = createShaderFromScriptElement(gl, "2d-vertex-shader");
	fragmentShader = createShaderFromScriptElement(gl, "2d-fragment-shader");
	alert('vertex shader is ' + vertexShader);
	alert('fragment shader is ' + fragmentShader);
	program = createProgram(gl, [ vertexShader, fragmentShader ]);
	gl.useProgram(program);

	var positionLocation;
	var texCoordLocation;
	var texCoordBuffer;

	function set_locations() {
		positionLocation = gl.getAttribLocation(program, "a_position");
		texCoordLocation = gl.getAttribLocation(program, "a_texCoord");
		var coords = [ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0,
				1.0 ];
		texCoordBuffer = gl.createBuffer();
		gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
		gl
				.bufferData(gl.ARRAY_BUFFER, new Float32Array(coords),
						gl.STATIC_DRAW);
		gl.enableVertexAttribArray(texCoordLocation);
		gl.vertexAttribPointer(texCoordLocation, 2, gl.FLOAT, false, 0, 0);
	}
	set_locations();

	var texture;
	function make_texture() {
		texture = gl.createTexture();
		gl.bindTexture(gl.TEXTURE_2D, texture);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

		// Upload the image into the texture.
		gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, canvas.width, canvas.height,
				0, gl.RGBA, gl.UNSIGNED_BYTE, view);
	}
	make_texture();

	var resolutionLocation;
	var buffer;
	function set_uniforms() {
		// lookup uniforms
		resolutionLocation = gl.getUniformLocation(program, "u_resolution");
		// set the resolution
		gl.uniform2f(resolutionLocation, canvas.width, canvas.height);
		// Create a buffer for the position of the rectangle corners.
		buffer = gl.createBuffer();
		gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
		gl.enableVertexAttribArray(positionLocation);
		gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);
		// Set a rectangle the same size as the image.
		setRectangle(gl, 0, 0, canvas.width, canvas.height);
	}
	set_uniforms();

	var pending_data = null;
	var transitive_rescale = 1.0;

	function cleanup() {
		gl.bindBuffer(gl.ARRAY_BUFFER, null);
		gl.bindTexture(gl.TEXTURE_2D, null);
		gl.deleteBuffer(buffer);
		gl.deleteBuffer(texCoordBuffer);
		gl.deleteTexture(texture);
	}

	function tick() {
		if (going) {
			if (transitive_rescale != 1.0) {
				rescale(transitive_rescale);
				transitive_rescale = 1.0;
			}
			if (pending_data != null) {
				alert('about to update');
				view.set(pending_data);
				gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, canvas.width,
						canvas.height, gl.RGBA, gl.UNSIGNED_BYTE, view);
				gl.drawArrays(gl.TRIANGLES, 0, 6);
				pending_data = null;
			}
			// let's pretend the image data got modified when something
			// else called my_c.update() in the mean time
			// for (i = 0; i < w*h*4; view[i++] = randomInt(256));
			// update the texture from the new image data
			// gl.texSubImage2D(gl.TEXTURE_2D,0,0,0,canvas.width,canvas.height,
			// gl.RGBA,gl.UNSIGNED_BYTE,view);
			// gl.drawArrays(gl.TRIANGLES,0,6);
			requestAnimFrame(tick);
		} else {
			cleanup();
		}
	}

	function rescale(factor) {
		cleanup();
		canvas.width = canvas.width * factor;
		canvas.height = canvas.height * factor;
		set_locations();
		make_texture();
		set_uniforms();
	}

	function queue_rescale(factor) {
		transitive_rescale *= factor;
	}

	function queue_stop() {
		going = false;
	}

	function queue_update(data) {
		pending_data = data;
	}

	going = true;
	requestAnimFrame(tick);
	my_c.id = id;
	my_c.update = queue_update;
	my_c.stop = queue_stop;
	my_c.rescale = queue_rescale;
	my_c.scale = scale;
	return my_c;
};
