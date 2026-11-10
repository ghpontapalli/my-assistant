const vscode = require("vscode");

const PORTAL_URL = "http://127.0.0.1:4100";

class PithagorasViewProvider {
  constructor(extensionUri) {
    this._extensionUri = extensionUri;
    this._view = undefined;
  }

  resolveWebviewView(webviewView) {
    this._view = webviewView;
    webviewView.webview.options = {
      enableScripts: true,
      enableForms: true,
    };
    webviewView.webview.html = this._getHtml();
  }

  reload() {
    if (this._view) {
      this._view.webview.html = this._getHtml();
    }
  }

  _getHtml() {
    return `<!DOCTYPE html>
<html lang="en" style="height:100%;margin:0;padding:0;">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline' 'unsafe-eval'; frame-src *;">
  <style>
    html, body { height: 100%; margin: 0; padding: 0; background: #14151a; }
    #frame { width: 100%; height: 100%; border: none; display: block; }
    #loading {
      position: absolute; top: 0; left: 0; right: 0; bottom: 0;
      display: flex; flex-direction: column; align-items: center; justify-content: center;
      background: #14151a; color: #9396a5; font-family: sans-serif; font-size: 14px; gap: 12px;
    }
    .dot { width: 8px; height: 8px; background: #7c5cff; border-radius: 50%;
      display: inline-block; margin: 0 3px; animation: bounce 1.2s infinite; }
    .dot:nth-child(2) { animation-delay: 0.2s; }
    .dot:nth-child(3) { animation-delay: 0.4s; }
    @keyframes bounce { 0%,80%,100%{transform:translateY(0)} 40%{transform:translateY(-8px)} }
  </style>
</head>
<body>
  <div id="loading">
    <div>
      <span class="dot"></span>
      <span class="dot"></span>
      <span class="dot"></span>
    </div>
    <span>Connecting to Pithagoras...</span>
  </div>
  <iframe id="frame" src="${PORTAL_URL}" style="display:none;"
    onload="document.getElementById('loading').style.display='none';this.style.display='block';"
    onerror="document.querySelector('#loading span:last-child').textContent='Could not reach Pithagoras at ${PORTAL_URL}. Make sure it is running.';">
  </iframe>
</body>
</html>`;
  }
}

function activate(context) {
  const provider = new PithagorasViewProvider(context.extensionUri);

  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider("pithagoras.chat", provider, {
      webviewOptions: { retainContextWhenHidden: true },
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("pithagoras.open", () => {
      vscode.commands.executeCommand("pithagoras.chat.focus");
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("pithagoras.reload", () => {
      provider.reload();
    })
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
