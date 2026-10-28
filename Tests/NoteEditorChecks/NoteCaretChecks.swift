import AppKit
import SwiftUI
@main struct Checks {
 static func main() {
  var failures = 0
  func check(_ source: String,_ needle: String,_ occurrence: Int = 0) {
   let rendered = String(NoteMarkdown.inline(source).characters) as NSString
   let raw = source as NSString
   var displayRange = NSRange(location:0,length:rendered.length), sourceRange = NSRange(location:0,length:raw.length)
   var found = NSRange(), original = NSRange()
   for _ in 0...occurrence {
    found = rendered.range(of:needle,range:displayRange); original = raw.range(of:needle,range:sourceRange)
    if found.location == NSNotFound || original.location == NSNotFound { print("MISSING",source,needle); failures += 1; return }
    displayRange = NSRange(location:NSMaxRange(found),length:rendered.length - NSMaxRange(found))
    sourceRange = NSRange(location:NSMaxRange(original),length:raw.length - NSMaxRange(original))
   }
   let actual = NoteMarkdown.inlineSourceOffset(found.location,in:source)
   if actual != original.location { print("FAIL",source,needle,actual,"!=",original.location); failures += 1 }
  }
  check("普通 **中文粗体** *中文斜体* `代码 **原样**` 😀","中文粗体")
  check("普通 **中文粗体** *中文斜体* `代码 **原样**` 😀","中文斜体")
  check("普通 **中文粗体** *中文斜体* `代码 **原样**` 😀","代码")
  check("普通 **中文粗体** *中文斜体* `代码 **原样**` 😀","😀")
  check("<u>under</u> 后面","under")
  check("`<u>literal</u>`","<u>")
  check("`<u>literal</u>`","literal")
  check("**重复** 重复","重复",1)
  check("[链接](https://repeat.test/xx) 后面","后面")
  check("\\*普通\\* **加粗**","普通")
  if NoteMarkdown.inlineSourceOffset(1,in:"&amp;a") != 5 { print("FAIL entity caret"); failures += 1 }
  check("第一行\n**第二行**\n第三行","第二行")
  check("第一行\n**第二行**\n第三行","第三行")
  check("**👨‍👩‍👧‍👦家庭** 😀","家庭")
  check("``a ` b`` 普通","a ` b")
  func checkTyping(_ initial: String,_ selection: NSRange,_ words: [String],marked: Bool = false) {
   var saved = initial
   let parent = NoteTextEditor(text:Binding(get:{ saved },set:{ saved = $0 }),height:.constant(30),undo:UndoManager())
   let coordinator = parent.makeCoordinator()
   let view = GrowingNoteTextView(frame:NSRect(x:0,y:0,width:360,height:100))
   view.isRichText = false; view.string = initial
   coordinator.style(view); view.delegate = coordinator; view.setSelectedRange(selection)
   var expected = initial as NSString, caret = selection
   for word in words {
    expected = expected.replacingCharacters(in:caret,with:word) as NSString
    let end = caret.location + word.utf16.count
    if marked {
     view.setMarkedText("pinyin",selectedRange:NSRange(location:6,length:0),replacementRange:caret)
     let composition = view.attributedString(), compositionSelection = view.selectedRange(), previousSaved = saved
     coordinator.synchronizeText(view); coordinator.style(view)
     if !view.hasMarkedText() || view.attributedString() != composition || view.selectedRange() != compositionSelection || saved != previousSaved {
      print("FAIL active composition changed"); failures += 1
     }
    }
    view.insertText(word,replacementRange:marked ? NSRange(location:NSNotFound,length:0) : caret)
    RunLoop.main.run(until:Date(timeIntervalSinceNow:0.01))
    if view.string != expected as String || saved != expected as String || view.selectedRange() != NSRange(location:end,length:0) {
     print("FAIL typing",marked,word,"text:",view.string,"saved:",saved,"caret:",view.selectedRange(),"expected:",end); failures += 1
    }
    caret = NSRange(location:end,length:0)
   }
  }
  checkTyping("",NSRange(location:0,length:0),["hello"," ","world"])
  checkTyping("",NSRange(location:0,length:0),["中文","输入","连续选词"],marked:true)
  checkTyping("开头 结尾",NSRange(location:3,length:0),["中文","单词"],marked:true)
  checkTyping("替换旧词末尾",NSRange(location:2,length:2),["新词","😀"],marked:true)
  checkTyping("## 标题\n**加粗** ",NSRange(location:13,length:0),["中文","👨‍👩‍👧‍👦","继续"],marked:true)
  // SwiftUI can refresh from a selection/height change before its binding snapshot catches up.
  var snapshot = "前缀 "
  var inputSaved = snapshot
  var refreshDuringInput: (() -> Void)?
  let inputParent = NoteTextEditor(text:Binding(get:{ snapshot },set:{ value in
   inputSaved = value; refreshDuringInput?(); snapshot = value
  }),height:.constant(30),undo:UndoManager())
  let inputCoordinator = inputParent.makeCoordinator()
  let inputView = GrowingNoteTextView(frame:NSRect(x:0,y:0,width:360,height:100))
  inputView.string = snapshot; inputView.isRichText = false
  inputCoordinator.style(inputView); inputView.delegate = inputCoordinator
  inputView.setSelectedRange(NSRange(location:snapshot.utf16.count,length:0))
  refreshDuringInput = { inputCoordinator.synchronizeText(inputView); inputCoordinator.style(inputView) }
  for (index,word) in ["中文","词语","😀","hello"].enumerated() {
   let expected = inputSaved + word
   if index < 3 { inputView.setMarkedText("pinyin",selectedRange:NSRange(location:6,length:0),replacementRange:NSRange(location:NSNotFound,length:0)) }
   inputView.insertText(word,replacementRange:NSRange(location:NSNotFound,length:0))
   inputCoordinator.synchronizeText(inputView)
   RunLoop.main.run(until:Date(timeIntervalSinceNow:0.01))
   if inputView.string != expected || inputSaved != expected || inputView.selectedRange() != NSRange(location:expected.utf16.count,length:0) {
    print("FAIL binding refresh during input",word,inputView.string,inputView.selectedRange()); failures += 1
   }
  }
  snapshot = "撤销后的内容"
  inputCoordinator.synchronizeText(inputView)
  if inputView.string != snapshot { print("FAIL external text update"); failures += 1 }
  let selectionToStyle = NSRange(location:0,length:2)
  inputView.setSelectedRange(selectionToStyle)
  inputCoordinator.style(inputView)
  if inputView.selectedRange() != selectionToStyle { print("FAIL styling selection preservation"); failures += 1 }
  let source = "## 标题 **强调**\n\n> 引用 *内容*\n\n- [ ] 任务 **文字**\n\n```swift\nlet x = 1\n```"
  for (block,word) in zip(NoteMarkdown.blocks(source),["强调","内容","文字","let"]) {
   let displayed = block.kind == .code ? block.text : String(NoteMarkdown.inline(block.text).characters)
   let range = (displayed as NSString).range(of:word)
   let actual = NoteMarkdown.sourceCaret(in:block,renderedOffset:range.location)
   let expected = (source as NSString).range(of:word).location
   if actual != expected { print("BLOCK FAIL",word,actual,expected); failures += 1 }
  }
  let editor = GrowingNoteTextView()
  editor.string = "已经写好的内容"
  var saved = "", continued = 0, savedWhenContinuing = ""
  editor.commit = { saved = $0 }; editor.continueWriting = { savedWhenContinuing = saved; continued += 1 }
  let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
  if !editor.handleMarkdownKey(event) || continued != 1 || saved != editor.string || savedWhenContinuing != editor.string { print("FAIL CmdReturn commit/order"); failures += 1 }
  _ = editor.handleMarkdownKey(event)
  if continued != 1 { print("FAIL duplicate continue"); failures += 1 }
  let enter = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
  if editor.handleMarkdownKey(enter) { print("FAIL normal Enter intercepted"); failures += 1 }
  let label = NoteInlineText.Label(wrappingLabelWithString:"")
  label.frame = NSRect(x:0,y:0,width:320,height:24)
  label.attributedStringValue = NoteMarkdown.attributedInline("前缀 **中文** 尾部",font:.systemFont(ofSize:13))
  let range = (label.attributedStringValue.string as NSString).range(of:"中文")
  let prefixWidth = label.attributedStringValue.attributedSubstring(from:NSRange(location:0,length:range.location)).size().width
  let glyphWidth = label.attributedStringValue.attributedSubstring(from:NSRange(location:range.location,length:1)).size().width
  let drawing = label.cell!.titleRect(forBounds:label.bounds)
  var hitOffset = -1
  label.activated = { offset,_ in hitOffset = offset }
  let click = NSEvent.mouseEvent(with:.leftMouseDown,location:label.convert(NSPoint(x:drawing.minX + prefixWidth + glyphWidth * 0.2,y:drawing.minY + 5),to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!
  label.mouseDown(with:click)
  if hitOffset != range.location { print("FAIL native glyph hit",hitOffset,range.location); failures += 1 }
  let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:300,height:200))
  let document = NSView(frame:NSRect(x:0,y:0,width:300,height:2000))
  scroll.documentView = document
  scroll.contentView.scroll(to:NSPoint(x:0,y:500))
  let anchor = NoteEditAnchor(view:document)
  let expectedOrigin = scroll.contentView.bounds.origin
  scroll.contentView.scroll(to:NSPoint(x:0,y:800))
  anchor.restore()
  if scroll.contentView.bounds.origin != expectedOrigin { print("FAIL scroll anchor restore"); failures += 1 }
  editor.insertText("新一条内容",replacementRange:NSRange(location:0,length:editor.string.utf16.count))
  let keypad = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:76)!
  if !editor.handleMarkdownKey(keypad) || continued != 2 || savedWhenContinuing != editor.string { print("FAIL keypad CmdEnter after input"); failures += 1 }
  if failures > 0 { exit(1) }
  print("Passed: continuous typing, IME composition/commit, reentrant binding refresh, deferred styling, external updates, Chinese/emoji caret mapping, native click, viewport restore and CmdEnter")
 }
}
