package webview

import "text/css"

/// The user agent stylesheet: what HTML looks like before a page says
/// otherwise, after the standard's rendering section.
public func UserAgentCSS() -> string {
    return userAgentCSS
}

let userAgentCSS = """
html, body, address, blockquote, center, div, figure, figcaption, footer, form, header, hr, legend,
listing, main, p, plaintext, pre, xmp, article, aside, h1, h2, h3, h4, h5, h6, hgroup, nav, section,
dir, dd, dl, dt, menu, ol, ul, li, table, caption, colgroup, col, thead, tbody, tfoot, tr, td, th,
fieldset, details, summary, dialog, optgroup, option, select, search, noscript { display: block; }
head, link, meta, script, style, title, base, template, area, datalist, param, rp, [hidden] { display: none; }
input[type=hidden] { display: none; }

html { font-family: system-ui; font-size: 16px; color: #000000; }
body { margin: 8px; }
h1 { font-size: 2em; margin: 0.67em 0; font-weight: bold; }
h2 { font-size: 1.5em; margin: 0.83em 0; font-weight: bold; }
h3 { font-size: 1.17em; margin: 1em 0; font-weight: bold; }
h4 { font-size: 1em; margin: 1.33em 0; font-weight: bold; }
h5 { font-size: 0.83em; margin: 1.67em 0; font-weight: bold; }
h6 { font-size: 0.67em; margin: 2.33em 0; font-weight: bold; }
p, dl, blockquote, figure, dir, menu, ol, ul, pre, listing, plaintext, xmp { margin: 1em 0; }
blockquote, figure { margin-left: 40px; margin-right: 40px; }
address { font-style: italic; }
dd { margin-left: 40px; }
dir, menu, ol, ul { padding-left: 40px; }
ol { list-style-type: decimal; }
ul, menu, dir { list-style-type: disc; }
ol ul, ul ul, menu ul, dir ul { list-style-type: circle; }
ol ol ul, ol ul ul, ul ol ul, ul ul ul { list-style-type: square; }
li { display: list-item; }
ol ol, ol ul, ul ol, ul ul, dl dl, dl ol, dl ul { margin-top: 0; margin-bottom: 0; }
hr { color: gray; border-style: inset; border-width: 1px; margin: 0.5em auto; }
pre, listing, plaintext, xmp, code, kbd, samp, tt { font-family: monospace; }
pre, listing, plaintext, xmp { white-space: pre; }
b, strong { font-weight: bolder; }
i, cite, em, var, dfn, address { font-style: italic; }
u, ins { text-decoration: underline; }
s, strike, del { text-decoration: line-through; }
abbr[title], acronym[title] { text-decoration: underline; }
small { font-size: smaller; }
big { font-size: larger; }
sub { vertical-align: sub; font-size: smaller; }
sup { vertical-align: super; font-size: smaller; }
mark { background-color: yellow; color: black; }
a:link, a[href] { color: #0000ee; text-decoration: underline; cursor: pointer; }
a:visited { color: #551a8b; }
a:active { color: #ff0000; }
center { text-align: center; }
nobr { white-space: nowrap; }
img, video, canvas, iframe, embed, object, svg { display: inline-block; }
br { display: inline; }
table { display: table; box-sizing: border-box; border-spacing: 2px; border-collapse: separate; text-indent: 0; }
caption { display: table-caption; text-align: center; }
thead { display: table-header-group; vertical-align: middle; }
tbody { display: table-row-group; vertical-align: middle; }
tfoot { display: table-footer-group; vertical-align: middle; }
tr { display: table-row; vertical-align: inherit; }
td, th { display: table-cell; vertical-align: inherit; padding: 1px; }
th { font-weight: bold; text-align: center; }
colgroup { display: table-column-group; }
col { display: table-column; }
table[border] td, table[border] th { border-width: 1px; border-style: inset; }
fieldset { margin-left: 2px; margin-right: 2px; padding: 0.35em 0.75em 0.625em; border: 2px groove #c0c0c0; }
legend { padding-left: 2px; padding-right: 2px; }
details > summary:first-of-type { display: list-item; list-style-type: disclosure-closed; }
details[open] > summary:first-of-type { list-style-type: disclosure-open; }
details:not([open]) > *:not(summary:first-of-type) { display: none; }
summary { cursor: default; }
input, textarea, select, button {
  display: inline-block; font-family: system-ui; font-size: 13.33px; color: #000000; letter-spacing: normal;
  word-spacing: normal; line-height: normal; text-transform: none; text-indent: 0; text-align: start;
  box-sizing: border-box; vertical-align: middle;
}
input, textarea { background-color: #ffffff; border: 1px solid #767676; border-radius: 3px; padding: 3px 6px; cursor: text; }
input { width: 150px; height: 24px; }
textarea { width: 200px; height: 60px; white-space: pre-wrap; resize: none; }
select { background-color: #ffffff; border: 1px solid #767676; border-radius: 4px; padding: 2px 24px 2px 6px; height: 24px; cursor: default; }
button, input[type=submit], input[type=button], input[type=reset] {
  background-color: #efefef; border: 1px solid #767676; border-radius: 4px; padding: 3px 10px; cursor: default;
  text-align: center; width: auto; height: auto; white-space: nowrap;
}
input[type=checkbox], input[type=radio] { width: 13px; height: 13px; padding: 0; margin: 3px 3px 3px 4px; border-radius: 2px; cursor: default; vertical-align: middle; }
input[type=radio] { border-radius: 50%; }
input[type=range], input[type=color], input[type=file] { border: none; background-color: transparent; }
input:disabled, textarea:disabled, select:disabled, button:disabled { color: #a0a0a0; background-color: #fafafa; cursor: default; }
input::placeholder, textarea::placeholder { color: #757575; }
input:focus, textarea:focus, select:focus, button:focus { outline-width: 2px; outline-color: #005fcc; }
label { cursor: default; }
progress, meter { display: inline-block; width: 160px; height: 16px; }
"""

/// The user agent's rules, parsed once for every view.
var userAgentRules: RuleSet? = nil

public func UserAgentRules() -> RuleSet {
    if let rs = userAgentRules { return rs }
    let rs = RuleSet()
    rs.Add(css.Parse(userAgentCSS))
    userAgentRules = rs
    return rs
}
