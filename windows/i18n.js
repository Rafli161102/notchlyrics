'use strict';

const LANGUAGES = [
  { code: 'en', name: 'English' },
  { code: 'id', name: 'Bahasa Indonesia' },
  { code: 'ja', name: '日本語' },
  { code: 'ko', name: '한국어' },
  { code: 'zh-Hans', name: '简体中文' },
  { code: 'es', name: 'Español' }
];

const TRANSLATIONS = {
  appHeader: {
    en: 'NotchLyrics for Windows',
    id: 'NotchLyrics untuk Windows',
    ja: 'NotchLyrics Windows版',
    ko: 'Windows용 NotchLyrics',
    'zh-Hans': 'NotchLyrics Windows 版',
    es: 'NotchLyrics para Windows'
  },
  idleStatus: {
    en: 'Play music in Chrome, Edge, Spotify, or Apple Music',
    id: 'Putar musik di Chrome, Edge, Spotify, atau Apple Music',
    ja: 'Chrome・Edge・Spotify・Apple Musicで再生してください',
    ko: 'Chrome, Edge, Spotify 또는 Apple Music에서 음악을 재생하세요',
    'zh-Hans': '请在 Chrome、Edge、Spotify 或 Apple Music 中播放音乐',
    es: 'Reproduce música en Chrome, Edge, Spotify o Apple Music'
  },
  searchingLyrics: {
    en: 'Searching lyrics:',
    id: 'Mencari lirik:',
    ja: '歌詞を検索中:',
    ko: '가사 검색 중:',
    'zh-Hans': '正在搜索歌词:',
    es: 'Buscando letra:'
  },
  styleAttached: {
    en: 'Notch Style: Attached Bezel',
    id: 'Gaya Notch: Menempel Bezel Atas',
    ja: 'ノッチスタイル: 上ベゼル一体型',
    ko: '노치 스타일: 상단 베젤 부착형',
    'zh-Hans': '刘海样式: 顶部贴合',
    es: 'Estilo Notch: Bisel Superior'
  },
  styleFloating: {
    en: 'Notch Style: Floating Island',
    id: 'Gaya Notch: Dynamic Island Mengambang',
    ja: 'ノッチスタイル: フローティングアイランド',
    ko: '노치 스타일: 플로팅 아일랜드',
    'zh-Hans': '刘海样式: 悬浮灵动岛',
    es: 'Estilo Notch: Isla Flotante'
  },
  styleStrip: {
    en: 'Notch Style: Edge Dock Strip',
    id: 'Gaya Notch: Strip Bezel Penuh',
    ja: 'ノッチスタイル: ワイドトップバー',
    ko: '노치 스타일: 와이드 베젤 스트립',
    'zh-Hans': '刘海样式: 顶部宽条',
    es: 'Estilo Notch: Tira Superior Ancha'
  },
  romanizeLyrics: {
    en: 'Romanize Non-Latin Lyrics',
    id: 'Romanisasi Lirik Non-Latin',
    ja: '非ラテン文字の歌詞をローマ字化',
    ko: '비라틴 가사 로마자 변환',
    'zh-Hans': '非拉丁歌词罗马音注音',
    es: 'Romanizar Letras No Latinas'
  },
  languageMenu: {
    en: 'Settings Language',
    id: 'Bahasa Pengaturan',
    ja: '設定言語',
    ko: '설정 언어',
    'zh-Hans': '设置语言',
    es: 'Idioma de Ajustes'
  },
  quitApp: {
    en: 'Quit NotchLyrics',
    id: 'Keluar NotchLyrics',
    ja: 'NotchLyrics を終了',
    ko: 'NotchLyrics 종료',
    'zh-Hans': '退出 NotchLyrics',
    es: 'Salir de NotchLyrics'
  }
};

function t(lang, key) {
  const code = LANGUAGES.some((l) => l.code === lang) ? lang : 'en';
  const row = TRANSLATIONS[key];
  if (!row) return key;
  return row[code] || row.en || key;
}

module.exports = { LANGUAGES, TRANSLATIONS, t };
