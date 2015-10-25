(function(f){"object"==typeof exports&&"object"==typeof module?f(require("../../lib/codemirror")):"function"==typeof define&&define.amd?define(["../../lib/codemirror"],f):f(CodeMirror)})(function(f){function l(a){"object"==typeof a&&(this.minChars=a.minChars,this.style=a.style,this.showToken=a.showToken,this.delay=a.delay,this.wordsOnly=a.wordsOnly);null==this.style&&(this.style="matchhighlight");null==this.minChars&&(this.minChars=2);null==this.delay&&(this.delay=100);null==this.wordsOnly&&(this.wordsOnly=
!1);this.overlay=this.timeout=null}function g(a){var c=a.state.matchHighlighter;clearTimeout(c.timeout);c.timeout=setTimeout(function(){h(a)},c.delay)}function h(a){a.operation(function(){var c=a.state.matchHighlighter;c.overlay&&(a.removeOverlay(c.overlay),c.overlay=null);if(!a.somethingSelected()&&c.showToken){for(var d=!0===c.showToken?/[\w$]/:c.showToken,b=a.getCursor(),e=a.getLine(b.line),f=b=b.ch;b&&d.test(e.charAt(b-1));)--b;for(;f<e.length&&d.test(e.charAt(f));)++f;b<f&&a.addOverlay(c.overlay=
k(e.slice(b,f),d,c.style))}else if(d=a.getCursor("from"),e=a.getCursor("to"),d.line==e.line){if(b=c.wordsOnly){a:if(null!==a.getRange(d,e).match(/^\w+$/)){if(0<d.ch&&(b={line:d.line,ch:d.ch-1},b=a.getRange(b,d),null===b.match(/\W/))){b=!1;break a}if(e.ch<a.getLine(d.line).length&&(b={line:e.line,ch:e.ch+1},b=a.getRange(e,b),null===b.match(/\W/))){b=!1;break a}b=!0}else b=!1;b=!b}b||(d=a.getRange(d,e).replace(/^\s+|\s+$/g,""),d.length>=c.minChars&&a.addOverlay(c.overlay=k(d,!1,c.style)))}})}function k(a,
c,d){return{token:function(b){var e;if(e=b.match(a))(e=!c)||(e=(!b.start||!c.test(b.string.charAt(b.start-1)))&&(b.pos==b.string.length||!c.test(b.string.charAt(b.pos))));if(e)return d;b.next();b.skipTo(a.charAt(0))||b.skipToEnd()}}}f.defineOption("highlightSelectionMatches",!1,function(a,c,d){d&&d!=f.Init&&((d=a.state.matchHighlighter.overlay)&&a.removeOverlay(d),clearTimeout(a.state.matchHighlighter.timeout),a.state.matchHighlighter=null,a.off("cursorActivity",g));c&&(a.state.matchHighlighter=new l(c),
h(a),a.on("cursorActivity",g))})});