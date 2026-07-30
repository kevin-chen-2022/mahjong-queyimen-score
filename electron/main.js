// Electron main process for 成都麻将·缺一门计分
const { app, BrowserWindow, Menu } = require('electron');
const path = require('path');

// Default window size: optimal desktop browser size for this page
const DEFAULT_WIDTH = 1200;
const DEFAULT_HEIGHT = 820;

function createWindow() {
  const win = new BrowserWindow({
    width: DEFAULT_WIDTH,
    height: DEFAULT_HEIGHT,
    minWidth: 420,
    minHeight: 640,
    title: '成都麻将 · 缺一门计分',
    icon: path.join(__dirname, '..', 'build-resources', 'icon.png'),
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  // Hide default menu bar (keep Alt to toggle)
  Menu.setApplicationMenu(null);

  win.loadFile(path.join(__dirname, '..', 'chengdu-mahjong.html'));
}

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
