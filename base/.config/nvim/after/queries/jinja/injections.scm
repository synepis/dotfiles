;; extends

; Inject HTML into template content blocks outside of Jinja tags
((content) @injection.content
  (#set! injection.language "html")
  (#set! injection.combined))
