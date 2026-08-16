;; extends

; 1. Inject SQL into strings containing SQL keywords
(string
  (string_content) @injection.content
  (#match? @injection.content "^[ \t\n]*([sS][eE][lL][eE][cC][tT]|[iI][nN][sS][eE][rR][tT]|[uU][pP][dD][aA][tT][eE]|[dD][eE][lL][eE][tT][eE]|[cC][rR][eE][aA][tT][eE]|[dD][rR][oO][pP]|[aA][lL][tT][eE][rR]|[wW][iI][tT][hH])")
  (#set! injection.language "sql"))


; 2. Inject SQL into db.execute(...) or cursor.executemany(...)
(call
  function: (attribute
    attribute: (identifier) @_method
    (#match? @_method "execute|executemany"))
  arguments: (argument_list
    (string
      (string_content) @injection.content))
  (#set! injection.language "sql"))


; 3a. Direct call: render_template_string("...")
(call
  function: (identifier) @_func
  (#match? @_func "render_template_string")
  arguments: (argument_list
    (string
      (string_content) @injection.content))
  (#set! injection.language "jinja"))

; 3b. Module call: flask.render_template_string("...")
(call
  function: (attribute
    attribute: (identifier) @_method
    (#match? @_method "render_template_string"))
  arguments: (argument_list
    (string
      (string_content) @injection.content))
  (#set! injection.language "jinja"))
