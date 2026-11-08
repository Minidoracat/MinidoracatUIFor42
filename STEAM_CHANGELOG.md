[h1]Minidoracat UI Library for B42 42.21.0-0.18.2[/h1]
[i]2026-11-08[/i]

[b]English summary[/b]
[list]
[*] Fixed: in solid (non-see-through) windows, such as the safehouse admin panel, hovering a text box that has a tooltip drew a black box in the top-left corner of the screen, covering icons and window tabs. The black box is gone.
[*] The tooltip itself is now solid as intended; the text behind it no longer shows through.
[*] Mods that use this library need no update for this fix.
[/list]

[h3]🔧 修正[/h3]
[list]
[*] [b]滑鼠停在輸入欄上時，畫面左上角多出一塊黑色方塊[/b]：在不透明的視窗裡（例如安全屋的管理員面板），滑鼠停在有說明的輸入欄上，說明框跳出來的同時，畫面左上角會多一塊和說明框一樣寬的黑色方塊，蓋住旁邊的圖示、視窗的分頁或標題；說明框本身也還透出底下的字。0.15.1 起有這個問題，和頁面捲不捲動無關。現在黑色方塊不再出現，說明框照設計不透明。
[/list]
