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
  appHeaderLinux: {
    en: 'NotchLyrics for Linux',
    id: 'NotchLyrics untuk Linux',
    ja: 'NotchLyrics Linux版',
    ko: 'Linux용 NotchLyrics',
    'zh-Hans': 'NotchLyrics Linux 版',
    es: 'NotchLyrics para Linux'
  },
  idleStatus: {
    en: 'Play music in Chrome, Edge, Spotify, or Apple Music',
    id: 'Putar musik di Chrome, Edge, Spotify, atau Apple Music',
    ja: 'Chrome・Edge・Spotify・Apple Musicで再生してください',
    ko: 'Chrome, Edge, Spotify 또는 Apple Music에서 음악을 재생하세요',
    'zh-Hans': '请在 Chrome、Edge、Spotify 或 Apple Music 中播放音乐',
    es: 'Reproduce música en Chrome, Edge, Spotify o Apple Music'
  },
  idleStatusLinux: {
    en: 'Play music in Spotify, Chrome, Firefox, or VLC (MPRIS2)',
    id: 'Putar musik di Spotify, Chrome, Firefox, atau VLC (MPRIS2)',
    ja: 'Spotify・Chrome・Firefox・VLC で再生してください (MPRIS2)',
    ko: 'Spotify, Chrome, Firefox 또는 VLC에서 음악을 재생하세요 (MPRIS2)',
    'zh-Hans': '请在 Spotify、Chrome、Firefox 或 VLC 中播放音乐 (MPRIS2)',
    es: 'Reproduce música en Spotify, Chrome, Firefox o VLC (MPRIS2)'
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
  refetchLyrics: {
    en: 'Refetch Lyrics (Clear Cache)',
    id: 'Muat Ulang Lirik (Hapus Cache)',
    ja: '歌詞を再取得 (キャッシュ削除)',
    ko: '가사 다시 불러오기 (캐시 삭제)',
    'zh-Hans': '重新获取歌词 (清除缓存)',
    es: 'Volver a Buscar Letra (Limpiar Caché)'
  },
  manualOffsetMenu: {
    en: 'Manual Lyrics Offset',
    id: 'Offset Lirik Manual',
    ja: '手動歌詞オフセット',
    ko: '수동 가사 오프셋',
    'zh-Hans': '手动歌词时间偏移',
    es: 'Ajuste Manual de Letra'
  },
  offsetAhead50: {
    en: 'Advance (+0.5s)',
    id: 'Majukan (+0.5s)',
    ja: '早める (+0.5s)',
    ko: '빠르게 (+0.5s)',
    'zh-Hans': '提前 (+0.5s)',
    es: 'Adelantar (+0.5s)'
  },
  offsetAhead10: {
    en: 'Fine Advance (+0.1s)',
    id: 'Majukan Halus (+0.1s)',
    ja: '微調整で早める (+0.1s)',
    ko: '미세 빠르게 (+0.1s)',
    'zh-Hans': '微调提前 (+0.1s)',
    es: 'Adelanto Fino (+0.1s)'
  },
  offsetBack10: {
    en: 'Fine Delay (-0.1s)',
    id: 'Mundurkan Halus (-0.1s)',
    ja: '微調整で遅らせる (-0.1s)',
    ko: '미세 느리게 (-0.1s)',
    'zh-Hans': '微调延后 (-0.1s)',
    es: 'Retraso Fino (-0.1s)'
  },
  offsetBack50: {
    en: 'Delay (-0.5s)',
    id: 'Mundurkan (-0.5s)',
    ja: '遅らせる (-0.5s)',
    ko: '느리게 (-0.5s)',
    'zh-Hans': '延后 (-0.5s)',
    es: 'Retrasar (-0.5s)'
  },
  offsetReset: {
    en: 'Reset Offset (0.0s)',
    id: 'Reset Offset (0.0s)',
    ja: 'オフセットをリセット (0.0s)',
    ko: '오프셋 초기화 (0.0s)',
    'zh-Hans': '重置偏移 (0.0s)',
    es: 'Restablecer Ajuste (0.0s)'
  },
  languageMenu: {
    en: 'Settings Language',
    id: 'Bahasa Pengaturan',
    ja: '設定言語',
    ko: '설정 언어',
    'zh-Hans': '设置语言',
    es: 'Idioma de Ajustes'
  },
  aboutMenu: {
    en: 'About NotchLyrics...',
    id: 'Tentang NotchLyrics...',
    ja: 'NotchLyrics について...',
    ko: 'NotchLyrics 정보...',
    'zh-Hans': '关于 NotchLyrics...',
    es: 'Acerca de NotchLyrics...'
  },
  aboutDetail: {
    en: 'Real-time synchronized karaoke lyrics for Windows 10/11 (Golden Ratio OLED Notch + WinRT SMTC).\n\nSources: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\nLicense: MIT License\nRepository: github.com/Rafli161102/notchlyrics',
    id: 'Lirik karaoke tersinkronisasi real-time untuk Windows 10/11 (Golden Ratio OLED Notch + WinRT SMTC).\n\nSumber: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\nLisensi: MIT License\nRepositori: github.com/Rafli161102/notchlyrics',
    ja: 'Windows 10/11 向けのリアルタイム同期カラオケ歌詞オーバーレイ (OLED ノッチ + WinRT SMTC)。\n\n歌詞ソース: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\nライセンス: MIT License\nリポジトリ: github.com/Rafli161102/notchlyrics',
    ko: 'Windows 10/11용 실시간 동기화 가라오케 가사 오버레이 (OLED 노치 + WinRT SMTC).\n\n가사 출처: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\n라이선스: MIT License\n저장소: github.com/Rafli161102/notchlyrics',
    'zh-Hans': '面向 Windows 10/11 的实时同步卡拉OK歌词悬浮窗 (OLED 刘海屏 + WinRT SMTC)。\n\n歌词来源: LRCLIB、网易云 (YRC/LRC)、酷狗、酷我、Deezer、iTunes\n开源协议: MIT License\n代码仓库: github.com/Rafli161102/notchlyrics',
    es: 'Letras de karaoke sincronizadas en tiempo real para Windows 10/11 (Notch OLED + WinRT SMTC).\n\nFuentes: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\nLicencia: MIT License\nRepositorio: github.com/Rafli161102/notchlyrics'
  },
  aboutDetailLinux: {
    en: 'Real-time synchronized karaoke lyrics for Linux (Golden Ratio OLED Notch + MPRIS2).\n\nSources: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\nLicense: MIT License\nRepository: github.com/Rafli161102/notchlyrics',
    id: 'Lirik karaoke tersinkronisasi real-time untuk Linux (Golden Ratio OLED Notch + MPRIS2).\n\nSumber: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\nLisensi: MIT License\nRepositori: github.com/Rafli161102/notchlyrics',
    ja: 'Linux 向けのリアルタイム同期カラオケ歌詞オーバーレイ (OLED ノッチ + MPRIS2)。\n\n歌詞ソース: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\nライセンス: MIT License\nリポジトリ: github.com/Rafli161102/notchlyrics',
    ko: 'Linux용 실시간 동기화 가라오케 가사 오버레이 (OLED 노치 + MPRIS2).\n\n가사 출처: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\n라이선스: MIT License\n저장소: github.com/Rafli161102/notchlyrics',
    'zh-Hans': '面向 Linux 的实时同步卡拉OK歌词悬浮窗 (OLED 刘海屏 + MPRIS2)。\n\n歌词来源: LRCLIB、网易云 (YRC/LRC)、酷狗、酷我、Deezer、iTunes\n开源协议: MIT License\n代码仓库: github.com/Rafli161102/notchlyrics',
    es: 'Letras de karaoke sincronizadas en tiempo real para Linux (Notch OLED + MPRIS2).\n\nFuentes: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\nLicencia: MIT License\nRepositorio: github.com/Rafli161102/notchlyrics'
  },
  aboutOpenReleases: {
    en: 'GitHub Releases',
    id: 'Buka Rilis GitHub',
    ja: 'GitHub リリースを開く',
    ko: 'GitHub 릴리스 열기',
    'zh-Hans': '打开 GitHub 发布页',
    es: 'Abrir GitHub Releases'
  },
  aboutClose: {
    en: 'Close',
    id: 'Tutup',
    ja: '閉じる',
    ko: '닫기',
    'zh-Hans': '关闭',
    es: 'Cerrar'
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
