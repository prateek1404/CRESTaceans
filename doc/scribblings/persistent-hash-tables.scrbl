#lang scribble/doc
@(require scribble/manual)
 
@title[#:tag "persistent-hash-tables"]{Persistent functional hash tables}
    
@defidform[hash/eq/null]{Produces a new persistent hash table for which @racket[(hash/empty? _hash)] is equal to @racket[#t], therefore an empty persistent hash table where keys are compared with @racket[eq?].}

@defidform[hash/eqv/null]{Produces a new persistent hash table for which @racket[(hash/empty? _hash)] is equal to @racket[#t], therefore an empty persistent hash table where keys are compared with @racket[eqv?].}

@defidform[hash/equal/null]{Produces a new persistent hash table for which @racket[(hash/empty? _hash)] is equal to @racket[#t], therefore an empty persistent hash table where keys are compared with @racket[equal?].}

@defproc[(hash/persist? [v any/c]) boolean?]{Returns @racket[#t] if @racket[v] is a persistent hash table, @racket[#f] otherwise.}

@defproc[(hash/eq? [hash hash/persist?]) boolean?]{Returns @racket[#t] if the equality test for keys is @racket[eq?], @racket[#f] otherwise.}

@defproc[(hash/eqv? [hash hash/persist?]) boolean?]{Returns @racket[#t] if the equality test for keys is @racket[eqv?], @racket[#f] otherwise.}

@defproc[(hash/equal? [hash hash/persist?]) boolean?]{Returns @racket[#t] if the equality test for keys is @racket[equal?], @racket[#f] otherwise.}

@defproc[(list/hash [hash hash/persist?]
                    [lst list?]) hash/persist?]{Nondestructively produces a new persistent hash table @racket[hash\'] from the union of the contents
                                                of @racket[hash] and a list of key/value pairs given as input in the form of (k_0 v_0 ... ... k_i v_i). 
                                                If @racket[hash] contains a pair k_i/x for some value x then it will be replaced by k_i/v_i in 
                                                @racket[hash\'].}
                                      
@defproc[(hash/new [hash hash/persist?]
                   [key any/c]
                   [v any/c]
                   ...
                   ...) hash/persist?]{Equivalent to @racket[(list/hash hash lst)], but takes multiple arguments instead of a list of key/value pairs.}


@defproc[(pairs/hash [hash hash/persist?][lst list?]) hash/persist?]{Equivalent to @racket[(list/hash hash lst)], but takes as input a list of lists in the form of ((k_0 . v_0) ... (k_i . v_i)).}


@defproc[(vector/hash [hash hash/persist?][vec vector?]) hash/persist?]{Non-destructively creates a fresh hash table @racket[hash\'] that is the union of the contents of the hash table @racket[hash] and the contents of vector @racket[vec = #(k_0 v_0 k_1 v_1 ... k_{n-1} v_{n-1})]. Equivalent of @racket[(pairs/hash h ((k_0 . v_0) ... (k_i . v_i)))].}

@defproc[(vectors/hash [hash hash/persist?][keys vector?][values vector?]) hash/persist?]{Non-destructively creates a hash table @racket[hash\'] that is the union of the contents of the hash table @racket[hash] and the contents of vectors @racket[keys = #(k_0 k_1 ... k_{n-1})] corresponding to the keys and @racket[keys = #(v_0 v_1 ... v_{n-1})] corresponding to the respective keys' values.}


@defproc[(hash/cons [hash hash/persist?]
                    [key any/c]
                    [v any/c]) hash/persist?]{Produces a new persistent hash table @racket[hash\'] by merging the contents of @racket[hash] and
                                              the given key/value pair. If @racket[hash] contains @racket[key] then its value is replaced by @racket[v] in 
                                              the @racket[hash\'].}

@defproc[(hash/remove [hash hash/persist?]
                      [key any/c]) hash/persist?]{Produces a new persistent hash table @racket[hash\'] whose contents are identlical to @racket[hash]
                                                  but without the key/value pair indexed by @racket[key].}


@defproc[(hash=>vector/remove [hash hash/persist?][keys vector?]) hash/persist?]{Produces a new persistent hash table @racket[hash\'] whose contents are identlical to @racket[hash] but without the key/value pairs indexed by the contents of vector @racket[keys].}


@defproc[(hash/merge [hash1 hash/persist?]
                     [hash2 hash/persist?])hash/persist?]{Produces a new persistent hash table @racket[hash1\'] that is the merge of @racket[hash2] INTO
                                             @racket[hash1]. Any key/value pair in @racket[hash2] whose key duplicates a key appearing in 
                                             @racket[hash1] will replace the corresponding key/value pair in @racket[hash1]. The length of the 
                                             resulting hash table will be at most @racket[(+ (hash/length hash1) (hash/length hash2))].}
                     
@defproc[(hash=>list [hash hash/persist?]) list?]{Returns a list of the values of @racket[hash] in an unspecified order.}

@defproc[(hash=>pairs [hash hash/persist?]) list?]{Returns an association list ((k_0 . v_0) ...) of key/value pairs within @racket[hash].}

@defproc[(hash=>vector [hash hash/persist?]) vector?]{Returns a vector #(k_0 v_0 ... k_{n-1} v_{n-1}) of key/value pairs within @racket[hash].}

@defproc[(hash/insertion=>vector [hash hash/persist?]) vector?]{Return the contents of @racket[hash] as @racket[#(k_1 v_1 ... k_n v_n)] but respect the insertion order of the key/value pairs @racket[k_i/v_i], that is, @racket[k_i v_i] precedes @racket[k_j v_j if k_i/v_i] were added to the hash table before @racket[k_j/v_j].}

@defproc[(hash/keys [hash hash/persist?]) list?]{Returns the set of keys in @racket[hash] as a list.}

@defproc[(hash/values [hash hash/persist?]) list?]{Returns the set of values in @racket[hash] as a list.}


@defproc[(hash/ref [hash hash?]
                   [key any/c]
                   [failure any/c]) any/c]{Returns the value for @racket[key] in @racket[hash]. If no value is found for @racket[key], 
                   then @racket[failure] is returned as the result. @racket[failure] can as well be a procedure that is called in case @racket[key] 
                   is not in @racket[hash].}
                   
@defproc[(hash/car [hash hash/persist?]) any/c]{Returns the "first" key/value pair of hash table @racket[hash].}              
         
@defproc[(hash/cdr [hash hash/persist?]) list?]{Produces a new persistent hash table @racket[hash\'] in which the key/value pair returned by 
                                                  @racket[(hash/car hash)] is absent. Equivalent to @racket[(hash/remove hash (car (hash/car hash)))]
                                                  but considerably more efficient.} 
                                                                                   


@defproc[(hash/length [hash hash/persist?]) natural/exact?]{Returns the length of @racket[hash] (i.e., the number of key/value pairs in the 
                                                              persistent hash table).}                                                                                   

                                                                                   
@defproc[(hash/empty? [hash hash/persist?]) boolean?]{Returns @racket[#t] if @racket[(hash/length hash)] is equal to @racket[0],
                                                               otherwise returns @racket[#f].}


@defproc[(hash/contains? [hash hash/persist?]
                         [key any/c]) boolean?]{Returns @racket[#t] if @racket[hash] contains @racket[key] and @racket[#f] otherwise.}
                                               
                                               
@defproc[(hash/fold [hash hash/persist?]
                    [proc procedure?]
                    [seed any/c]) any/c]{Fold function @racket[proc] with @racket[seed] over all pairs in persistent hash table @racket[hash].@racket[f] accepts three arguments: key, value, and the most recently computed seed.}
  
                                        
@defproc[(hash/map [hash hash/persist?] 
                   [proc procedure?]) hash/persist?]{Apply function @racket[f] to each key/value pair in @racket[h] and return a hash table containing the results. @racket[f] accepts two arguments, a key and a value.}


@defproc[(hash/for-each [hash hash/persist?] 
                   [proc procedure?]) void?]{Applies @racket[proc] to each key/value pair in @racket[hash] and discards all results. The @racket[proc] function takes a single argument.}

@defproc[(hash/filter [hash hash/persist?] 
                   [proc procedure?]) hash/persist?]{Returns a persistent hash table containing only those key/value pairs in @racket[hash] for 
                                                     which @racket[(proc key value)] is @racket[#t].}
                                                  
@defproc[(hash/partition [hash hash/persist?] 
                   [proc procedure?]) hash/persist?]{Returns a pair of hash tables (hash-true . hash-false) in which hash table hash-true contains only 
                                                     those pairs of @racket[hash] for which predicate @racket[proc] returns @racket[#t] 
                                                     and hash table hash-false contains only those pairs of @racket[hash]for which predicate @racket[proc] returns @racket[#f]. @racket[proc] is a predicate of two arguments @racket[(proc key value)].}
                                                    
                                                   
