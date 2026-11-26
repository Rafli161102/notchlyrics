'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('NotchLyricsDesktop', {
  onState: (cb) => ipcRenderer.on('notch-state', (_event, state) => cb(state)),
  sendCommand: (command) => ipcRenderer.send('notch-command', command),
  setHovered: (expanded) => ipcRenderer.send('notch-hover', Boolean(expanded))
});
