# Regenerate demo/demo.gif with charmbracelet/vhs:
#
#   ./demo/setup.sh            # build the scratch repo at /tmp/demo-attest
#   vhs demo/demo.tape         # render demo.gif, then move it into site/public
#
# Requires `attest` and `vhs` on PATH (brew install corvidlabs/tap/attest charmbracelet/tap/vhs).
Output demo.gif
Set FontSize 20
Set Width 1200
Set Height 800
Set Padding 30
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms
Hide
Type "cd /tmp/demo-attest && clear"
Enter
Show
Sleep 500ms
Type "# attest: record who reviewed this commit, verifiably"
Sleep 600ms
Enter
Type "attest sign --reviewer human:leif --confidence 0.92 --tests-passed --sign"
Sleep 400ms
Enter
Sleep 1500ms
Type "attest log"
Sleep 400ms
Enter
Sleep 2500ms
Type "attest verify --policy release.json"
Sleep 400ms
Enter
Sleep 3500ms
