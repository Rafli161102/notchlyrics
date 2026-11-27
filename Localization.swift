import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case english = "en"
    case indonesian = "id"
    case japanese = "ja"
    case korean = "ko"
    case chineseSimplified = "zh-Hans"
    case spanish = "es"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .indonesian: return "Bahasa Indonesia"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .chineseSimplified: return "简体中文"
        case .spanish: return "Español"
        }
    }
}

enum L10n {
    static let didChangeNotification = Notification.Name("TouchBarLyricsLanguageDidChange")
    private static let defaultsKey = "appLanguage"

    static var currentLanguage: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: defaultsKey),
               let lang = AppLanguage(rawValue: raw) {
                return lang
            }
            return .english
        }
        set {
            let prev = currentLanguage
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            if prev != newValue {
                NotificationCenter.default.post(name: didChangeNotification, object: newValue)
            }
        }
    }

    static func tr(_ key: String) -> String {
        let lang = currentLanguage
        if let entry = translations[key] {
            return entry[lang] ?? entry[.english] ?? key
        }
        return key
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), arguments: args)
    }

    static let translations: [String: [AppLanguage: String]] = [
        // Display Modes
        "display.touchBar": [
            .english: "Touch Bar", .indonesian: "Touch Bar", .japanese: "Touch Bar",
            .korean: "Touch Bar", .chineseSimplified: "Touch Bar", .spanish: "Touch Bar"
        ],
        "display.notch": [
            .english: "Notch", .indonesian: "Notch", .japanese: "ノッチ",
            .korean: "노치", .chineseSimplified: "刘海屏", .spanish: "Notch"
        ],
        "display.both": [
            .english: "Touch Bar + Notch", .indonesian: "Touch Bar + Notch", .japanese: "Touch Bar + ノッチ",
            .korean: "Touch Bar + 노치", .chineseSimplified: "Touch Bar + 刘海屏", .spanish: "Touch Bar + Notch"
        ],
        "display.hidden": [
            .english: "Hide", .indonesian: "Sembunyikan", .japanese: "非表示",
            .korean: "숨기기", .chineseSimplified: "隐藏", .spanish: "Ocultar"
        ],

        // Font Styles
        "font.sans": [
            .english: "System Sans", .indonesian: "System Sans", .japanese: "システムゴシック",
            .korean: "시스템 산스", .chineseSimplified: "系统无衬线", .spanish: "System Sans"
        ],
        "font.rounded": [
            .english: "Rounded", .indonesian: "Rounded", .japanese: "丸ゴシック",
            .korean: "둥근 고딕", .chineseSimplified: "圆体", .spanish: "Redondeada"
        ],
        "font.serif": [
            .english: "Editorial Serif", .indonesian: "Editorial Serif", .japanese: "明朝体",
            .korean: "명조체", .chineseSimplified: "衬线体", .spanish: "Editorial Serif"
        ],
        "font.mono": [
            .english: "Monospace", .indonesian: "Monospace", .japanese: "等幅フォント",
            .korean: "고정폭", .chineseSimplified: "等宽字体", .spanish: "Monoespaciada"
        ],
        "font.avenir": [
            .english: "Avenir Next", .indonesian: "Avenir Next", .japanese: "Avenir Next",
            .korean: "Avenir Next", .chineseSimplified: "Avenir Next", .spanish: "Avenir Next"
        ],
        "font.futura": [
            .english: "Futura (Geometric)", .indonesian: "Futura (Geometris)", .japanese: "Futura (ジオメトリック)",
            .korean: "Futura (기하학체)", .chineseSimplified: "Futura (几何体)", .spanish: "Futura (Geométrica)"
        ],
        "font.gillSans": [
            .english: "Gill Sans", .indonesian: "Gill Sans", .japanese: "Gill Sans",
            .korean: "Gill Sans", .chineseSimplified: "Gill Sans", .spanish: "Gill Sans"
        ],
        "font.georgia": [
            .english: "Georgia (Serif)", .indonesian: "Georgia (Serif)", .japanese: "Georgia (セリフ)",
            .korean: "Georgia (세리프)", .chineseSimplified: "Georgia (经典衬线)", .spanish: "Georgia (Serif)"
        ],
        "font.helvetica": [
            .english: "Helvetica Neue", .indonesian: "Helvetica Neue", .japanese: "Helvetica Neue",
            .korean: "Helvetica Neue", .chineseSimplified: "Helvetica Neue", .spanish: "Helvetica Neue"
        ],
        "font.hiragino": [
            .english: "Hiragino Sans (Clean)", .indonesian: "Hiragino Sans (Bersih)", .japanese: "ヒラギノ角ゴ (CJK)",
            .korean: "히라기노 고딕", .chineseSimplified: "冬青黑体 (Hiragino)", .spanish: "Hiragino Sans"
        ],
        "font.markerFelt": [
            .english: "Marker Felt (Playful)", .indonesian: "Marker Felt (Santai)", .japanese: "Marker Felt (手書き風)",
            .korean: "Marker Felt (손글씨)", .chineseSimplified: "Marker Felt (手写风)", .spanish: "Marker Felt"
        ],

        // Layout Modes
        "layout.standard": [
            .english: "Balanced Classic", .indonesian: "Klasik Seimbang", .japanese: "バランス標準",
            .korean: "균형 클래식", .chineseSimplified: "经典均衡", .spanish: "Clásico Equilibrado"
        ],
        "layout.centeredMinimal": [
            .english: "Minimal Centered", .indonesian: "Tengah Minimal", .japanese: "中央ミニマル",
            .korean: "중앙 미니멀", .chineseSimplified: "居中极简", .spanish: "Centrado Minimal"
        ],
        "layout.rightFlow": [
            .english: "Left Lyrics + Right Title", .indonesian: "Lirik Kiri + Judul Kanan", .japanese: "左歌詞 + 右曲名",
            .korean: "왼쪽 가사 + 오른쪽 제목", .chineseSimplified: "左歌词 + 右歌名", .spanish: "Letra Izq. + Título Der."
        ],
        "layout.lyricsOnly": [
            .english: "Full Lyrics Focus", .indonesian: "Fokus Lirik Penuh", .japanese: "歌詞のみ集中",
            .korean: "가사 집중 모드", .chineseSimplified: "纯享歌词", .spanish: "Solo Letra Completa"
        ],

        // Slot Positions
        "slot.left": [
            .english: "Left Side", .indonesian: "Sisi Kiri", .japanese: "左側",
            .korean: "왼쪽", .chineseSimplified: "左侧", .spanish: "Lado Izquierdo"
        ],
        "slot.right": [
            .english: "Right Side", .indonesian: "Sisi Kanan", .japanese: "右側",
            .korean: "오른쪽", .chineseSimplified: "右侧", .spanish: "Lado Derecho"
        ],
        "slot.hidden": [
            .english: "Hide", .indonesian: "Sembunyikan", .japanese: "非表示",
            .korean: "숨기기", .chineseSimplified: "隐藏", .spanish: "Ocultar"
        ],

        // Backing Vocal Placement
        "backing.below": [
            .english: "Below Lead Vocal", .indonesian: "Di Bawah Vokal Utama", .japanese: "メイン歌詞の下",
            .korean: "메인 보컬 아래", .chineseSimplified: "主唱下方", .spanish: "Debajo de Voz Principal"
        ],
        "backing.above": [
            .english: "Above Lead Vocal", .indonesian: "Di Atas Vokal Utama", .japanese: "メイン歌詞の上",
            .korean: "메인 보컬 위", .chineseSimplified: "主唱上方", .spanish: "Encima de Voz Principal"
        ],
        "backing.inline": [
            .english: "Inline Single Row", .indonesian: "Sejajar 1 Baris", .japanese: "1行に並べる",
            .korean: "한 줄 나란히", .chineseSimplified: "单行并排", .spanish: "En Una Línea"
        ],

        // Text Align
        "align.center": [
            .english: "Center Align", .indonesian: "Rata Tengah", .japanese: "中央揃え",
            .korean: "가운데 정렬", .chineseSimplified: "居中对齐", .spanish: "Centrado"
        ],
        "align.left": [
            .english: "Left Align", .indonesian: "Rata Kiri", .japanese: "左揃え",
            .korean: "왼쪽 정렬", .chineseSimplified: "左对齐", .spanish: "Alineado a la Izquierda"
        ],
        "align.right": [
            .english: "Right Align", .indonesian: "Rata Kanan", .japanese: "右揃え",
            .korean: "오른쪽 정렬", .chineseSimplified: "右对齐", .spanish: "Alineado a la Derecha"
        ],

        // Progress Position
        "progress.bottom": [
            .english: "Bottom Bar", .indonesian: "Garis Bawah", .japanese: "下端ライン",
            .korean: "하단 바", .chineseSimplified: "底部进度条", .spanish: "Barra Inferior"
        ],
        "progress.top": [
            .english: "Top Bar", .indonesian: "Garis Atas", .japanese: "上端ライン",
            .korean: "상단 바", .chineseSimplified: "顶部进度条", .spanish: "Barra Superior"
        ],
        "progress.hidden": [
            .english: "Hide", .indonesian: "Sembunyikan", .japanese: "非表示",
            .korean: "숨기기", .chineseSimplified: "隐藏", .spanish: "Ocultar"
        ],

        // EQ Style
        "eq.bars": [
            .english: "EQ Bars + Dot", .indonesian: "Bar Equalizer + Titik", .japanese: "EQバー + ドット",
            .korean: "EQ 바 + 도트", .chineseSimplified: "均衡器条 + 圆点", .spanish: "Barras EQ + Punto"
        ],
        "eq.pulseDot": [
            .english: "Vocal Dot Only", .indonesian: "Titik Vokal Saja", .japanese: "ボーカルドットのみ",
            .korean: "보컬 도트만", .chineseSimplified: "仅人声圆点", .spanish: "Solo Punto Vocal"
        ],
        "eq.none": [
            .english: "Off", .indonesian: "Nonaktif", .japanese: "オフ",
            .korean: "끄기", .chineseSimplified: "关闭", .spanish: "Desactivado"
        ],

        // Line Transitions
        "trans.pushUp": [
            .english: "Push Up", .indonesian: "Dorong ke Atas", .japanese: "上へスライド",
            .korean: "위로 밀기", .chineseSimplified: "向上推入", .spanish: "Empujar Arriba"
        ],
        "trans.pushDown": [
            .english: "Push Down", .indonesian: "Turun ke Bawah", .japanese: "下へスライド",
            .korean: "아래로 밀기", .chineseSimplified: "向下推入", .spanish: "Empujar Abajo"
        ],
        "trans.slideLeft": [
            .english: "Slide Sideways", .indonesian: "Geser Samping", .japanese: "横スライド",
            .korean: "옆으로 슬라이드", .chineseSimplified: "横向滑动", .spanish: "Deslizar Lateral"
        ],
        "trans.crossfade": [
            .english: "Smooth Crossfade", .indonesian: "Crossfade Halus", .japanese: "スムーズフェード",
            .korean: "부드러운 페이드", .chineseSimplified: "柔和淡入淡出", .spanish: "Fundido Suave"
        ],
        "trans.zoomSoft": [
            .english: "Soft Scale Pop", .indonesian: "Pop Skala Lembut", .japanese: "ソフトズーム",
            .korean: "부드러운 줌 팝", .chineseSimplified: "柔和缩放", .spanish: "Escala Suave"
        ],
        "trans.none": [
            .english: "Instant (No Transition)", .indonesian: "Instan (Tanpa Transisi)", .japanese: "即時切替 (なし)",
            .korean: "즉시 전환 (없음)", .chineseSimplified: "即时切换 (无动画)", .spanish: "Instantáneo (Sin Transición)"
        ],
        "trans.slideRight": [
            .english: "Slide Right", .indonesian: "Geser ke Kanan", .japanese: "右へスライド",
            .korean: "오른쪽으로 슬라이드", .chineseSimplified: "向右滑入", .spanish: "Deslizar Derecha"
        ],
        "trans.scaleFade": [
            .english: "Cinematic Bloom", .indonesian: "Mekar Sinematik", .japanese: "シネマティックブルーム",
            .korean: "시네마틱 블룸", .chineseSimplified: "电影感绽放", .spanish: "Brote Cinemático"
        ],
        "trans.elasticBounce": [
            .english: "Elastic Spring", .indonesian: "Pantul Elastis", .japanese: "エラスティックスプリング",
            .korean: "탄성 스프링", .chineseSimplified: "弹性回弹", .spanish: "Rebote Elástico"
        ],

        // Word Animations
        "word.karaokeLift": [
            .english: "Karaoke + Syllable Lift", .indonesian: "Karaoke + Angkat Huruf", .japanese: "カラオケ + 文字リフト",
            .korean: "가라오케 + 글자 리프트", .chineseSimplified: "卡拉OK + 逐字跃动", .spanish: "Karaoke + Elevación"
        ],
        "word.smoothWipe": [
            .english: "Smooth Word Color Wipe", .indonesian: "Sapuan Warna Per Kata", .japanese: "スムーズカラーワイプ",
            .korean: "단어별 컬러 와이프", .chineseSimplified: "逐词平滑扫色", .spanish: "Barrido de Color por Palabra"
        ],
        "word.typewriter": [
            .english: "Gradual Typewriter", .indonesian: "Ketik Huruf Bertahap", .japanese: "タイプライター表示",
            .korean: "타자기 효과", .chineseSimplified: "逐字打字机", .spanish: "Máquina de Escribir"
        ],
        "word.glowPulse": [
            .english: "Reactive Bold Glow", .indonesian: "Sorot Tebal Reaktif", .japanese: "ダイナミック太字発光",
            .korean: "반응형 볼드 글로우", .chineseSimplified: "动态加粗高亮", .spanish: "Brillo Reactivo"
        ],
        "word.waveRipple": [
            .english: "Wave Ripple (Flowing)", .indonesian: "Ombak Mengalir (Wave)", .japanese: "ウェーブリップル (波紋)",
            .korean: "웨이브 리플 (물결)", .chineseSimplified: "波浪律动", .spanish: "Onda Fluida"
        ],
        "word.springPop": [
            .english: "Spring Pop (Bouncy)", .indonesian: "Pop Pegas (Membal)", .japanese: "スプリングポップ",
            .korean: "스프링 팝 (통통 튀기)", .chineseSimplified: "弹簧跃起", .spanish: "Salto Elástico"
        ],
        "word.spotlightGlow": [
            .english: "Stage Spotlight Glow", .indonesian: "Sorot Panggung (Spotlight)", .japanese: "スポットライト発光",
            .korean: "스테이지 스포트라이트", .chineseSimplified: "舞台聚光灯", .spanish: "Foco Escénico"
        ],
        "word.neonBounce": [
            .english: "Neon Pulse + Bounce", .indonesian: "Denyut Neon + Pantul", .japanese: "ネオンパルスバウンス",
            .korean: "네온 펄스 바운스", .chineseSimplified: "霓虹脉动", .spanish: "Pulso Neón"
        ],
        "word.elasticScale": [
            .english: "Elastic Beat Zoom", .indonesian: "Zoom Ketukan Elastis", .japanese: "エラスティックズーム",
            .korean: "일래스틱 비트 줌", .chineseSimplified: "节拍弹性放大", .spanish: "Zoom Rítmico"
        ],
        "word.letterDrop": [
            .english: "Cascade Drop Reveal", .indonesian: "Jatuh Beruntun (Drop)", .japanese: "カスケードドロップ",
            .korean: "캐스케이드 드롭", .chineseSimplified: "逐字瀑布落入", .spanish: "Cascada Descendente"
        ],
        "word.solid": [
            .english: "Static Solid", .indonesian: "Statis Penuh", .japanese: "固定表示",
            .korean: "고정 표시", .chineseSimplified: "静态常亮", .spanish: "Sólido Estático"
        ],

        // Color Sync Modes
        "color.adaptive": [
            .english: "Adaptive Artwork (Balanced)", .indonesian: "Adaptif Sampul (Seimbang)", .japanese: "アートワーク連動 (標準)",
            .korean: "앨범 아트 연동 (균형)", .chineseSimplified: "自适应专辑色 (均衡)", .spanish: "Carátula Adaptativa"
        ],
        "color.vivid": [
            .english: "Vivid Artwork Match", .indonesian: "Sampul Lagu Kuat", .japanese: "鮮やかなアートワーク色",
            .korean: "선명한 앨범 색상", .chineseSimplified: "高饱和专辑色", .spanish: "Carátula Intensa"
        ],
        "color.themeOnly": [
            .english: "Custom Theme Colors Only", .indonesian: "Warna Tema Kustom Saja", .japanese: "カスタムテーマ色のみ",
            .korean: "사용자 지정 테마색만", .chineseSimplified: "仅使用自定义主题色", .spanish: "Solo Colores del Tema"
        ],

        // Notch Styles
        "notch.attachedBezel": [
            .english: "Attached Top Bezel", .indonesian: "Menempel Bezel Atas", .japanese: "上ベゼル一体型",
            .korean: "상단 베젤 부착형", .chineseSimplified: "顶部刘海贴合", .spanish: "Bisel Superior Unido"
        ],
        "notch.floatingIsland": [
            .english: "Floating Dynamic Island", .indonesian: "Dynamic Island Mengambang", .japanese: "フローティングアイランド",
            .korean: "플로팅 다이내믹 아일랜드", .chineseSimplified: "悬浮灵动岛", .spanish: "Isla Dinámica Flotante"
        ],
        "notch.edgeDockStrip": [
            .english: "Full Bezel Strip", .indonesian: "Strip Bezel Penuh", .japanese: "ワイドトップバー",
            .korean: "와이드 베젤 스트립", .chineseSimplified: "顶部宽条贴合", .spanish: "Tira Superior Ancha"
        ],

        // Vocal Sync Modes
        "syncMode.balanced": [
            .english: "Auto Balanced", .indonesian: "Otomatis Seimbang", .japanese: "自動バランス",
            .korean: "자동 균형", .chineseSimplified: "自动均衡", .spanish: "Automático Equilibrado"
        ],
        "syncMode.strictCrowded": [
            .english: "Stable (Crowded Vocals / Chorus)", .indonesian: "Stabil (Vokal Ramai / Chorus)", .japanese: "安定 (ボーカル過密・サビ向け)",
            .korean: "안정 (보컬 밀집 / 코러스)", .chineseSimplified: "稳定 (密集人声 / 副歌)", .spanish: "Estable (Coros Densos)"
        ],
        "syncMode.fastLock": [
            .english: "Aggressive (Fast Lock)", .indonesian: "Agresif (Cepat Kunci)", .japanese: "高速ロック (積極追従)",
            .korean: "빠른 잠금 (적극 동기화)", .chineseSimplified: "积极锁定 (快速跟随)", .spanish: "Agresivo (Bloqueo Rápido)"
        ],
        "syncMode.manual": [
            .english: "Manual (Fixed Offset)", .indonesian: "Manual (Offset Tetap)", .japanese: "手動 (固定オフセット)",
            .korean: "수동 (고정 오프셋)", .chineseSimplified: "手动 (固定偏移)", .spanish: "Manual (Compensación Fija)"
        ],

        // App Status & Menu Bar
        "status.noActiveTrack": [
            .english: "No active track", .indonesian: "Tidak ada lagu aktif", .japanese: "再生中の曲はありません",
            .korean: "재생 중인 곡 없음", .chineseSimplified: "暂无播放曲目", .spanish: "Sin pista activa"
        ],
        "status.lyricsSource": [
            .english: "Lyrics source: %@", .indonesian: "Sumber lirik: %@", .japanese: "歌詞ソース: %@",
            .korean: "가사 출처: %@", .chineseSimplified: "歌词来源: %@", .spanish: "Fuente de letra: %@"
        ],
        "status.readingBpm": [
            .english: "Reading BPM...", .indonesian: "Membaca BPM...", .japanese: "BPM計測中...",
            .korean: "BPM 측정 중...", .chineseSimplified: "检测 BPM...", .spanish: "Leyendo BPM..."
        ],
        "status.bpmValue": [
            .english: "%d BPM", .indonesian: "%d BPM", .japanese: "%d BPM",
            .korean: "%d BPM", .chineseSimplified: "%d BPM", .spanish: "%d BPM"
        ],
        "status.tempoLine": [
            .english: "Tempo: %@ | Length: %02d:%02d | Word Speed: %.2fx",
            .indonesian: "Tempo: %@ | Panjang: %02d:%02d | Word Speed: %.2fx",
            .japanese: "テンポ: %@ | 長さ: %02d:%02d | 速度: %.2fx",
            .korean: "템포: %@ | 길이: %02d:%02d | 단어 속도: %.2fx",
            .chineseSimplified: "节奏: %@ | 时长: %02d:%02d | 字速: %.2fx",
            .spanish: "Tempo: %@ | Duración: %02d:%02d | Velocidad: %.2fx"
        ],
        "status.autoSyncOff": [
            .english: "Vocal Auto-Sync: Off", .indonesian: "Auto-Sync Vokal: Nonaktif", .japanese: "ボーカル自動同期: オフ",
            .korean: "보컬 자동 동기화: 끔", .chineseSimplified: "人声自动同步: 关闭", .spanish: "Auto-Sync Vocal: Desactivado"
        ],
        "status.playInSafari": [
            .english: "Play music in Safari", .indonesian: "Putar lagu di Safari", .japanese: "Safariで音楽を再生してください",
            .korean: "Safari에서 음악을 재생하세요", .chineseSimplified: "请在 Safari 中播放音乐", .spanish: "Reproduce música en Safari"
        ],
        "status.waitingMedia": [
            .english: "Waiting for media player (Music/Spotify/Safari)...",
            .indonesian: "Menunggu pemutar media (Music/Spotify/Safari)...",
            .japanese: "音楽プレーヤーを待機中 (Music/Spotify/Safari)...",
            .korean: "미디어 플레이어 대기 중 (Music/Spotify/Safari)...",
            .chineseSimplified: "等待媒体播放器 (Music/Spotify/Safari)...",
            .spanish: "Esperando reproductor (Music/Spotify/Safari)..."
        ],
        "status.waitingSafariAudio": [
            .english: "Waiting for audio from Safari...",
            .indonesian: "Menunggu audio dari Safari...",
            .japanese: "Safariからの音声を待機中...",
            .korean: "Safari 오디오 대기 중...",
            .chineseSimplified: "等待 Safari 音频...",
            .spanish: "Esperando audio de Safari..."
        ],
        "status.searchingLyrics": [
            .english: "Searching lyrics: %@...",
            .indonesian: "Mencari lirik: %@...",
            .japanese: "歌詞を検索中: %@...",
            .korean: "가사 검색 중: %@...",
            .chineseSimplified: "正在搜索歌词: %@...",
            .spanish: "Buscando letra: %@..."
        ],
        "status.searchingOnline": [
            .english: "Searching online...", .indonesian: "Mencari online...", .japanese: "オンライン検索中...",
            .korean: "온라인 검색 중...", .chineseSimplified: "在线搜索中...", .spanish: "Buscando en línea..."
        ],

        // Menu Bar Actions
        "menu.showTouchBar": [
            .english: "Show Lyrics on Touch Bar", .indonesian: "Tampilkan Lirik di Touch Bar", .japanese: "Touch Barに歌詞を表示",
            .korean: "Touch Bar에 가사 표시", .chineseSimplified: "在 Touch Bar 显示歌词", .spanish: "Mostrar Letra en Touch Bar"
        ],
        "menu.hideTouchBar": [
            .english: "Hide Touch Bar Lyrics", .indonesian: "Sembunyikan Touch Bar Lirik", .japanese: "Touch Barの歌詞を隠す",
            .korean: "Touch Bar 가사 숨기기", .chineseSimplified: "隐藏 Touch Bar 歌词", .spanish: "Ocultar Letra de Touch Bar"
        ],
        "menu.displayOn": [
            .english: "Display Output: %@", .indonesian: "Tampilkan Lirik di: %@", .japanese: "表示先: %@",
            .korean: "표시 위치: %@", .chineseSimplified: "显示位置: %@", .spanish: "Mostrar en: %@"
        ],
        "menu.notchStyle": [
            .english: "Notch Style: %@", .indonesian: "Gaya Notch: %@", .japanese: "ノッチスタイル: %@",
            .korean: "노치 스타일: %@", .chineseSimplified: "刘海样式: %@", .spanish: "Estilo de Notch: %@"
        ],
        "menu.autoShow": [
            .english: "Auto-Show on Playback", .indonesian: "Otomatis Muncul Saat Memutar", .japanese: "再生時に自動表示",
            .korean: "재생 시 자동 표시", .chineseSimplified: "播放时自动显示", .spanish: "Mostrar Automáticamente al Reproducir"
        ],
        "menu.safariOnly": [
            .english: "Source: Safari Only", .indonesian: "Sumber: Hanya Safari", .japanese: "ソース: Safariのみ",
            .korean: "소스: Safari만 사용", .chineseSimplified: "来源: 仅 Safari", .spanish: "Fuente: Solo Safari"
        ],
        "menu.autoVocalSync": [
            .english: "Audio Vocal Auto-Sync", .indonesian: "Auto-Sync dari Audio Vokal", .japanese: "音声ボーカル自動同期",
            .korean: "오디오 보컬 자동 동기화", .chineseSimplified: "音频人声自动同步", .spanish: "Auto-Sync por Audio Vocal"
        ],
        "menu.syncMode": [
            .english: "Auto-Sync Mode: %@", .indonesian: "Mode Auto-Sync: %@", .japanese: "自動同期モード: %@",
            .korean: "자동 동기화 모드: %@", .chineseSimplified: "自动同步模式: %@", .spanish: "Modo Auto-Sync: %@"
        ],
        "menu.recalibrateSync": [
            .english: "Recalibrate Auto-Sync Now", .indonesian: "Kalibrasi Auto-Sync Ulang Sekarang", .japanese: "今すぐ自動同期を再調整",
            .korean: "지금 자동 동기화 재보정", .chineseSimplified: "立即重新校准自动同步", .spanish: "Recalibrar Auto-Sync Ahora"
        ],
        "menu.resetSyncOffset": [
            .english: "Reset Vocal Auto-Sync Offset", .indonesian: "Reset Offset Auto-Sync Vokal", .japanese: "自動同期オフセットをリセット",
            .korean: "보컬 자동 동기화 오프셋 초기화", .chineseSimplified: "重置人声自动同步偏移", .spanish: "Restablecer Compensación Auto-Sync"
        ],
        "menu.refreshLyrics": [
            .english: "Refetch Lyrics (Clear Cache)", .indonesian: "Muat Ulang Lirik (Hapus Cache)", .japanese: "歌詞を再取得 (キャッシュ削除)",
            .korean: "가사 다시 불러오기 (캐시 삭제)", .chineseSimplified: "重新获取歌词 (清除缓存)", .spanish: "Volver a Buscar Letra (Limpiar Caché)"
        ],
        "menu.manualOffset": [
            .english: "Manual Lyrics Offset: %@", .indonesian: "Offset Lirik Manual: %@", .japanese: "手動歌詞オフセット: %@",
            .korean: "수동 가사 오프셋: %@", .chineseSimplified: "手动歌词偏移: %@", .spanish: "Ajuste Manual: %@"
        ],
        "menu.nudgeAhead50": [
            .english: "Advance Lyrics (+0.5s)", .indonesian: "Majukan Lirik (+0.5s)", .japanese: "歌詞を早める (+0.5s)",
            .korean: "가사 빠르게 (+0.5s)", .chineseSimplified: "歌词提前 (+0.5s)", .spanish: "Adelantar (+0.5s)"
        ],
        "menu.nudgeAhead25": [
            .english: "Advance Lyrics Timing (+0.25s)", .indonesian: "Majukan Timing Lirik (+0.25s)", .japanese: "歌詞タイミングを早める (+0.25s)",
            .korean: "가사 타이밍 빠르게 (+0.25s)", .chineseSimplified: "歌词提前 (+0.25s)", .spanish: "Adelantar Letra (+0.25s)"
        ],
        "menu.nudgeAhead10": [
            .english: "Step Advance (+0.1s)", .indonesian: "Majukan (+0.1s)", .japanese: "少し早める (+0.1s)",
            .korean: "조금 빠르게 (+0.1s)", .chineseSimplified: "微调提前 (+0.1s)", .spanish: "Adelanto (+0.1s)"
        ],
        "menu.nudgeAhead05": [
            .english: "Fine Advance (+0.05s)", .indonesian: "Majukan Halus (+0.05s)", .japanese: "微調整で早める (+0.05s)",
            .korean: "미세 빠르게 (+0.05s)", .chineseSimplified: "微调提前 (+0.05s)", .spanish: "Adelanto Fino (+0.05s)"
        ],
        "menu.nudgeBack05": [
            .english: "Fine Delay (-0.05s)", .indonesian: "Mundurkan Halus (-0.05s)", .japanese: "微調整で遅らせる (-0.05s)",
            .korean: "미세 느리게 (-0.05s)", .chineseSimplified: "微调延后 (-0.05s)", .spanish: "Retraso Fino (-0.05s)"
        ],
        "menu.nudgeBack10": [
            .english: "Step Delay (-0.1s)", .indonesian: "Mundurkan (-0.1s)", .japanese: "少し遅らせる (-0.1s)",
            .korean: "조금 느리게 (-0.1s)", .chineseSimplified: "微调延后 (-0.1s)", .spanish: "Retraso (-0.1s)"
        ],
        "menu.nudgeBack25": [
            .english: "Delay Lyrics Timing (-0.25s)", .indonesian: "Mundurkan Timing Lirik (-0.25s)", .japanese: "歌詞タイミングを遅らせる (-0.25s)",
            .korean: "가사 타이밍 느리게 (-0.25s)", .chineseSimplified: "歌词延后 (-0.25s)", .spanish: "Retrasar Letra (-0.25s)"
        ],
        "menu.nudgeBack50": [
            .english: "Delay Lyrics (-0.5s)", .indonesian: "Mundurkan Lirik (-0.5s)", .japanese: "歌詞を遅らせる (-0.5s)",
            .korean: "가사 느리게 (-0.5s)", .chineseSimplified: "歌词延后 (-0.5s)", .spanish: "Retrasar (-0.5s)"
        ],
        "menu.resetManualOffset": [
            .english: "Reset Manual Offset (0.0s)", .indonesian: "Reset Offset Manual (0.0s)", .japanese: "手動オフセットをリセット (0.0s)",
            .korean: "수동 오프셋 초기화 (0.0s)", .chineseSimplified: "重置手动偏移 (0.0s)", .spanish: "Restablecer Ajuste (0.0s)"
        ],
        "menu.romanize": [
            .english: "Romanize Lyrics (Romaji/Pinyin)", .indonesian: "Romanisasi Lirik (Romaji/Pinyin)", .japanese: "歌詞をローマ字化 (Romaji/Pinyin)",
            .korean: "가사 로마자 표기 (Romaji/Pinyin)", .chineseSimplified: "歌词罗马音注音", .spanish: "Romanizar Letras (Romaji/Pinyin)"
        ],
        "menu.charAnim": [
            .english: "Per-Character Karaoke Animation", .indonesian: "Animasi Per Huruf", .japanese: "文字ごとのカラオケアニメーション",
            .korean: "글자 단위 가라오케 애니메이션", .chineseSimplified: "逐字卡拉OK动画", .spanish: "Animación por Carácter"
        ],
        "menu.artworkColors": [
            .english: "Match Colors to Album Artwork", .indonesian: "Warna Mengikuti Artwork Lagu", .japanese: "アルバムアートに色を合わせる",
            .korean: "앨범 아트에 색상 맞추기", .chineseSimplified: "歌词颜色跟随专辑封面", .spanish: "Adaptar Colores a la Carátula"
        ],
        "menu.theme": [
            .english: "Theme: %@", .indonesian: "Tema: %@", .japanese: "テーマ: %@",
            .korean: "테마: %@", .chineseSimplified: "主题: %@", .spanish: "Tema: %@"
        ],
        "menu.customizeStudio": [
            .english: "Customize Theme, Layout & Animation...", .indonesian: "Kustomisasi Tema, Tata Letak & Animasi...", .japanese: "テーマ・レイアウト・アニメーション設定...",
            .korean: "테마, 레이아웃 및 애니메이션 설정...", .chineseSimplified: "自定义主题、布局与动画...", .spanish: "Personalizar Tema, Diseño y Animación..."
        ],
        "menu.language": [
            .english: "Settings Language: %@", .indonesian: "Bahasa Pengaturan: %@", .japanese: "設定言語: %@",
            .korean: "설정 언어: %@", .chineseSimplified: "设置语言: %@", .spanish: "Idioma de Ajustes: %@"
        ],
        "menu.quit": [
            .english: "Quit TouchBarLyrics", .indonesian: "Keluar TouchBarLyrics", .japanese: "TouchBarLyrics を終了",
            .korean: "TouchBarLyrics 종료", .chineseSimplified: "退出 TouchBarLyrics", .spanish: "Salir de TouchBarLyrics"
        ],
        "menu.about": [
            .english: "About NotchLyrics v%@...", .indonesian: "Tentang NotchLyrics v%@...", .japanese: "NotchLyrics v%@ について...",
            .korean: "NotchLyrics v%@ 정보...", .chineseSimplified: "关于 NotchLyrics v%@...", .spanish: "Acerca de NotchLyrics v%@..."
        ],
        "about.title": [
            .english: "NotchLyrics (TouchBarLyrics) v%@ (%@)",
            .indonesian: "NotchLyrics (TouchBarLyrics) v%@ (%@)",
            .japanese: "NotchLyrics (TouchBarLyrics) v%@ (%@)",
            .korean: "NotchLyrics (TouchBarLyrics) v%@ (%@)",
            .chineseSimplified: "NotchLyrics (TouchBarLyrics) v%@ (%@)",
            .spanish: "NotchLyrics (TouchBarLyrics) v%@ (%@)"
        ],
        "about.body": [
            .english: "Real-time synchronized karaoke lyrics for macOS Touch Bar & Notch.\n\nSources: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes, Lyrics.ovh\nEngine: CoreAudio Vocal Auto-Sync, BPM & Multi-Language Settings\nLicense: MIT License\nRepository: github.com/Rafli161102/notchlyrics",
            .indonesian: "Lirik karaoke tersinkronisasi real-time untuk macOS Touch Bar & Notch.\n\nSumber: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes, Lyrics.ovh\nMesin: Auto-Sync Audio Vokal CoreAudio, BPM & Pengaturan 6 Bahasa\nLisensi: MIT License\nRepositori: github.com/Rafli161102/notchlyrics",
            .japanese: "macOS Touch Bar & ノッチ向けのリアルタイム同期カラオケ歌詞。\n\n歌詞ソース: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\n機能: CoreAudio 音声自動同期・BPM・6言語設定 UI\nライセンス: MIT License\nリポジトリ: github.com/Rafli161102/notchlyrics",
            .korean: "macOS Touch Bar 및 노치용 실시간 동기화 가라오케 가사.\n\n가사 출처: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\n기능: CoreAudio 보컬 자동 동기화, BPM, 6개 언어 설정\n라이선스: MIT License\n저장소: github.com/Rafli161102/notchlyrics",
            .chineseSimplified: "面向 macOS Touch Bar 与刘海屏的实时同步卡拉OK歌词。\n\n歌词来源: LRCLIB、网易云 (YRC/LRC)、酷狗、酷我、Deezer、iTunes\n引擎: CoreAudio 人声自动同步、BPM 与 6 国语言界面\n开源协议: MIT License\n代码仓库: github.com/Rafli161102/notchlyrics",
            .spanish: "Letras de karaoke sincronizadas en tiempo real para macOS Touch Bar y Notch.\n\nFuentes: LRCLIB, NetEase (YRC/LRC), Kugou, Kuwo, Deezer, iTunes\nMotor: Auto-Sync vocal CoreAudio, BPM y 6 idiomas\nLicencia: MIT License\nRepositorio: github.com/Rafli161102/notchlyrics"
        ],
        "about.openReleases": [
            .english: "GitHub Releases", .indonesian: "Buka Rilis GitHub", .japanese: "GitHub リリースを開く",
            .korean: "GitHub 릴리스 열기", .chineseSimplified: "打开 GitHub 发布页", .spanish: "Abrir GitHub Releases"
        ],
        "about.close": [
            .english: "Close", .indonesian: "Tutup", .japanese: "閉じる",
            .korean: "닫기", .chineseSimplified: "关闭", .spanish: "Cerrar"
        ],

        // Vocal Auto-Sync Engine Statuses
        "sync.standby": [
            .english: "Standby", .indonesian: "Standby", .japanese: "待機中",
            .korean: "대기 중", .chineseSimplified: "待机中", .spanish: "En Espera"
        ],
        "sync.needPermission": [
            .english: "Needs System Audio permission (timestamp fallback)",
            .indonesian: "Butuh izin System Audio (fallback timestamp)",
            .japanese: "システム音声の権限が必要です (タイムスタンプ補完)",
            .korean: "시스템 오디오 권한 필요 (타임스탬프 대체)",
            .chineseSimplified: "需要系统音频权限 (已回退时间戳)",
            .spanish: "Requiere permiso de Audio del Sistema (usando marcas)"
        ],
        "sync.tapFailed": [
            .english: "Failed to create audio tap", .indonesian: "Gagal membuat audio tap", .japanese: "オーディオタップの作成に失敗",
            .korean: "오디오 탭 생성 실패", .chineseSimplified: "创建音频采集失败", .spanish: "Error al crear captura de audio"
        ],
        "sync.monitorFailed": [
            .english: "Failed to start audio monitor", .indonesian: "Gagal memulai audio monitor", .japanese: "オーディオ監視の開始に失敗",
            .korean: "오디오 모니터 시작 실패", .chineseSimplified: "启动音频监听失败", .spanish: "Error al iniciar monitor de audio"
        ],
        "sync.tapDenied": [
            .english: "Audio tap denied (timestamp fallback)", .indonesian: "Audio tap ditolak (fallback timestamp)", .japanese: "音声キャプチャが拒否されました",
            .korean: "오디오 탭 거부됨 (타임스탬프 대체)", .chineseSimplified: "音频采集被拒绝 (回退时间戳)", .spanish: "Captura de audio denegada"
        ],
        "sync.listening": [
            .english: "Active (listening for vocals...)", .indonesian: "Aktif (mendengar vokal...)", .japanese: "有効 (ボーカル聴取中...)",
            .korean: "활성 (보컬 분석 중...)", .chineseSimplified: "已启用 (正在监听人声...)", .spanish: "Activo (escuchando voz...)"
        ],
        "sync.analyzing": [
            .english: "Analyzing vocals & BPM...", .indonesian: "Menganalisa vokal & BPM...", .japanese: "ボーカルとBPMを解析中...",
            .korean: "보컬 및 BPM 분석 중...", .chineseSimplified: "正在分析人声与 BPM...", .spanish: "Analizando voz y BPM..."
        ],
        "sync.reset": [
            .english: "Vocal Auto-Sync: Reset (0.00s)", .indonesian: "Auto-Sync Vokal: Direset (0.00s)", .japanese: "自動同期: リセット (0.00s)",
            .korean: "보컬 자동 동기화: 초기화됨 (0.00s)", .chineseSimplified: "人声自动同步: 已重置 (0.00s)", .spanish: "Auto-Sync Vocal: Restablecido (0.00s)"
        ],
        "sync.realigning": [
            .english: "Re-aligning playback position...", .indonesian: "Menyelaraskan ulang posisi...", .japanese: "再生位置を再同期中...",
            .korean: "재생 위치 재정렬 중...", .chineseSimplified: "正在重新对齐播放进度...", .spanish: "Reajustando posición..."
        ],
        "sync.manualFixed": [
            .english: "Auto-Sync: Manual (Fixed Offset)", .indonesian: "Auto-Sync: Manual (Offset Tetap)", .japanese: "自動同期: 手動 (固定オフセット)",
            .korean: "자동 동기화: 수동 (고정 오프셋)", .chineseSimplified: "自动同步: 手动 (固定偏移)", .spanish: "Auto-Sync: Manual (Fijo)"
        ],
        "sync.calibrating": [
            .english: "Calibrating vocals (%d%%)...", .indonesian: "Kalibrasi vokal (%d%%)...", .japanese: "ボーカル較正中 (%d%%)...",
            .korean: "보컬 보정 중 (%d%%)...", .chineseSimplified: "正在校准人声 (%d%%)...", .spanish: "Calibrando voz (%d%%)..."
        ],
        "sync.waitingVocal": [
            .english: "Auto-Sync: Waiting for clear vocals...", .indonesian: "Auto-Sync: Menunggu vokal jelas...", .japanese: "自動同期: 明瞭なボーカルを待機中...",
            .korean: "자동 동기화: 선명한 보컬 대기 중...", .chineseSimplified: "自动同步: 等待清晰人声...", .spanish: "Auto-Sync: Esperando voz clara..."
        ],
        "sync.waitingLyrics": [
            .english: "Auto-Sync: Waiting for lyrics entry...", .indonesian: "Auto-Sync: Menunggu masuk lirik...", .japanese: "自動同期: 歌詞開始を待機中...",
            .korean: "자동 동기화: 가사 시작 대기 중...", .chineseSimplified: "自动同步: 等待歌词进入...", .spanish: "Auto-Sync: Esperando entrada de letra..."
        ],
        "sync.balancedZero": [
            .english: "%@Auto-Sync: 0.00s (Clarity %d%%)", .indonesian: "%@Auto-Sync: 0.00s (Clarity %d%%)", .japanese: "%@自動同期: 0.00s (明瞭度 %d%%)",
            .korean: "%@자동 동기화: 0.00s (선명도 %d%%)", .chineseSimplified: "%@自动同步: 0.00s (清晰度 %d%%)", .spanish: "%@Auto-Sync: 0.00s (Claridad %d%%)"
        ],

        // Accessibility Labels
        "a11y.prevTrack": [
            .english: "Previous track", .indonesian: "Lagu sebelumnya", .japanese: "前の曲",
            .korean: "이전 트랙", .chineseSimplified: "上一首", .spanish: "Pista anterior"
        ],
        "a11y.playPause": [
            .english: "Play or pause", .indonesian: "Putar atau jeda", .japanese: "再生または一時停止",
            .korean: "재생 또는 일시정지", .chineseSimplified: "播放或暂停", .spanish: "Reproducir o pausar"
        ],
        "a11y.nextTrack": [
            .english: "Next track", .indonesian: "Lagu berikutnya", .japanese: "次の曲",
            .korean: "다음 트랙", .chineseSimplified: "下一首", .spanish: "Siguiente pista"
        ],

        // Studio Window
        "studio.windowTitle": [
            .english: "Theme, Layout & Animation Studio", .indonesian: "Studio Tema, Tata Letak & Animasi", .japanese: "テーマ・レイアウト・アニメーション スタジオ",
            .korean: "테마, 레이아웃 및 애니메이션 스튜디오", .chineseSimplified: "主题、布局与动画工作室", .spanish: "Estudio de Tema, Diseño y Animación"
        ],
        "studio.languageLabel": [
            .english: "Language:", .indonesian: "Bahasa:", .japanese: "言語:",
            .korean: "언어:", .chineseSimplified: "语言:", .spanish: "Idioma:"
        ],
        "studio.themeLabel": [
            .english: "Theme:", .indonesian: "Tema:", .japanese: "テーマ:",
            .korean: "테마:", .chineseSimplified: "主题:", .spanish: "Tema:"
        ],
        "studio.themeNamePlaceholder": [
            .english: "Custom theme name", .indonesian: "Nama tema kustom", .japanese: "カスタムテーマ名",
            .korean: "사용자 테마 이름", .chineseSimplified: "自定义主题名称", .spanish: "Nombre del tema"
        ],
        "studio.duplicateBtn": [
            .english: "New / Duplicate", .indonesian: "Buat Baru / Duplikat", .japanese: "新規 / 複製",
            .korean: "새로 만들기 / 복제", .chineseSimplified: "新建 / 复制", .spanish: "Nuevo / Duplicar"
        ],
        "studio.deleteBtn": [
            .english: "Delete", .indonesian: "Hapus", .japanese: "削除",
            .korean: "삭제", .chineseSimplified: "删除", .spanish: "Eliminar"
        ],
        "studio.tab.layout": [
            .english: "Layout & Text", .indonesian: "Tata Letak & Teks", .japanese: "レイアウトとテキスト",
            .korean: "레이아웃 및 텍스트", .chineseSimplified: "布局与文字", .spanish: "Diseño y Texto"
        ],
        "studio.tab.colors": [
            .english: "Colors & Artwork", .indonesian: "Warna & Tema Lagu", .japanese: "カラーとアートワーク",
            .korean: "색상 및 앨범 테마", .chineseSimplified: "配色与封面", .spanish: "Colores y Carátula"
        ],
        "studio.tab.animation": [
            .english: "Animation & Sync", .indonesian: "Animasi & Sinkronisasi", .japanese: "アニメーションと同期",
            .korean: "애니메이션 및 동기화", .chineseSimplified: "动画与同步", .spanish: "Animación y Sincronía"
        ],
        "studio.btn.openJson": [
            .english: "Open themes.json...", .indonesian: "Buka themes.json...", .japanese: "themes.json を開く...",
            .korean: "themes.json 열기...", .chineseSimplified: "打开 themes.json...", .spanish: "Abrir themes.json..."
        ],
        "studio.btn.resetPresets": [
            .english: "Reset Presets", .indonesian: "Reset Preset", .japanese: "プリセットをリセット",
            .korean: "프리셋 초기화", .chineseSimplified: "重置预设", .spanish: "Restablecer Ajustes"
        ],
        "studio.btn.saveApply": [
            .english: "Save & Apply", .indonesian: "Simpan & Terapkan", .japanese: "保存して適用",
            .korean: "저장 및 적용", .chineseSimplified: "保存并应用", .spanish: "Guardar y Aplicar"
        ],
        "studio.pad.tight": [
            .english: "Tight (4 pt)", .indonesian: "Ketat (4 pt)", .japanese: "狭め (4 pt)",
            .korean: "좁게 (4 pt)", .chineseSimplified: "紧凑 (4 pt)", .spanish: "Ajustado (4 pt)"
        ],
        "studio.pad.standard": [
            .english: "Standard (8 pt)", .indonesian: "Standar (8 pt)", .japanese: "標準 (8 pt)",
            .korean: "표준 (8 pt)", .chineseSimplified: "标准 (8 pt)", .spanish: "Estándar (8 pt)"
        ],
        "studio.pad.wide": [
            .english: "Spacious (16 pt)", .indonesian: "Lega (16 pt)", .japanese: "広め (16 pt)",
            .korean: "넓게 (16 pt)", .chineseSimplified: "宽松 (16 pt)", .spanish: "Amplio (16 pt)"
        ],
        "studio.radius.sharp": [
            .english: "Sharp (0)", .indonesian: "Tajam (0)", .japanese: "シャープ (0)",
            .korean: "직각 (0)", .chineseSimplified: "直角 (0)", .spanish: "Recto (0)"
        ],
        "studio.radius.tactile": [
            .english: "Tactile (4)", .indonesian: "Tactile (4)", .japanese: "標準丸 (4)",
            .korean: "적당한 둥글기 (4)", .chineseSimplified: "微圆角 (4)", .spanish: "Táctil (4)"
        ],
        "studio.radius.rounded": [
            .english: "Rounded (6)", .indonesian: "Rounded (6)", .japanese: "丸型 (6)",
            .korean: "둥글게 (6)", .chineseSimplified: "圆角 (6)", .spanish: "Redondeado (6)"
        ],
        "studio.label.layoutMode": [
            .english: "Layout Pattern", .indonesian: "Pola Tata Letak", .japanese: "レイアウトパターン",
            .korean: "레이아웃 패턴", .chineseSimplified: "布局模式", .spanish: "Patrón de Diseño"
        ],
        "studio.label.textAlign": [
            .english: "Lyrics Alignment", .indonesian: "Perataan Lirik", .japanese: "歌詞の配置",
            .korean: "가사 정렬", .chineseSimplified: "歌词对齐", .spanish: "Alineación"
        ],
        "studio.label.trackPos": [
            .english: "Track Title Position", .indonesian: "Posisi Judul Lagu", .japanese: "曲名の位置",
            .korean: "곡 제목 위치", .chineseSimplified: "歌名位置", .spanish: "Posición del Título"
        ],
        "studio.label.controlsPos": [
            .english: "Play/Pause Buttons", .indonesian: "Tombol Play/Pause", .japanese: "再生ボタン位置",
            .korean: "재생/일시정지 버튼", .chineseSimplified: "播放按钮位置", .spanish: "Botones de Control"
        ],
        "studio.label.eqPos": [
            .english: "Indicator / EQ Pos", .indonesian: "Posisi Indikator/EQ", .japanese: "EQ位置",
            .korean: "EQ 표시 위치", .chineseSimplified: "EQ 指示位置", .spanish: "Posición Indicador/EQ"
        ],
        "studio.label.eqStyle": [
            .english: "Equalizer Style", .indonesian: "Gaya Equalizer", .japanese: "イコライザースタイル",
            .korean: "이퀄라이저 스타일", .chineseSimplified: "均衡器样式", .spanish: "Estilo Ecualizador"
        ],
        "studio.label.backingPlacement": [
            .english: "Backing Position", .indonesian: "Posisi Back Vocal", .japanese: "バックコーラス配置",
            .korean: "백 보컬 위치", .chineseSimplified: "和声位置", .spanish: "Posición Coros"
        ],
        "studio.label.progressPos": [
            .english: "Progress Bar", .indonesian: "Garis Progress", .japanese: "プログレスバー",
            .korean: "진행 바", .chineseSimplified: "进度条", .spanish: "Barra de Progreso"
        ],
        "studio.label.font": [
            .english: "Font Family", .indonesian: "Jenis Font", .japanese: "フォント種類",
            .korean: "글꼴", .chineseSimplified: "字体样式", .spanish: "Tipografía"
        ],
        "studio.label.customFont": [
            .english: "System Font Override", .indonesian: "Font Bebas Sistem", .japanese: "システムフォント選択",
            .korean: "시스템 글꼴 선택", .chineseSimplified: "自由系统字体", .spanish: "Fuente del Sistema"
        ],
        "studio.font.presetDefault": [
            .english: "(Use Style Preset)", .indonesian: "(Ikuti Gaya Font)", .japanese: "(スタイル設定を使用)",
            .korean: "(스타일 프리셋 사용)", .chineseSimplified: "(跟随预设风格)", .spanish: "(Usar Estilo Predefinido)"
        ],
        "studio.label.backingSpacing": [
            .english: "Main-BG Gap (px)", .indonesian: "Jarak Main-BG (px)", .japanese: "メイン-コーラス間隔(px)",
            .korean: "메인-백 보컬 간격(px)", .chineseSimplified: "主唱和声间距(px)", .spanish: "Separación Voz-Coros(px)"
        ],
        "studio.label.mainSize": [
            .english: "Lead Vocal Size", .indonesian: "Ukuran Main Vocal", .japanese: "メイン歌詞サイズ",
            .korean: "메인 보컬 크기", .chineseSimplified: "主唱字号", .spanish: "Tamaño Voz Principal"
        ],
        "studio.label.backingSize": [
            .english: "Backing Vocal Size", .indonesian: "Ukuran Back Vocal", .japanese: "コーラス文字サイズ",
            .korean: "백 보컬 크기", .chineseSimplified: "和声字号", .spanish: "Tamaño Coros"
        ],
        "studio.label.backingTag": [
            .english: "Backing Label", .indonesian: "Tag Back Vocal", .japanese: "コーラスタグ",
            .korean: "백 보컬 태그", .chineseSimplified: "和声标签", .spanish: "Etiqueta Coros"
        ],
        "studio.label.padding": [
            .english: "Horizontal Margin", .indonesian: "Jarak Tepi", .japanese: "左右余白",
            .korean: "좌우 여백", .chineseSimplified: "边距", .spanish: "Margen Lateral"
        ],
        "studio.label.radius": [
            .english: "Corner Radius", .indonesian: "Kelengkungan Sudut", .japanese: "角丸",
            .korean: "모서리 둥글기", .chineseSimplified: "圆角大小", .spanish: "Radio de Esquinas"
        ],
        "studio.label.notchStyle": [
            .english: "Top Notch Style", .indonesian: "Gaya Notch Atas", .japanese: "上部ノッチスタイル",
            .korean: "상단 노치 스타일", .chineseSimplified: "顶部刘海样式", .spanish: "Estilo Notch Superior"
        ],
        "studio.label.showBorder": [
            .english: "Show Border", .indonesian: "Tampilan Border", .japanese: "枠線を表示",
            .korean: "테두리 표시", .chineseSimplified: "显示边框", .spanish: "Mostrar Borde"
        ],
        "studio.color.bg": [
            .english: "Background", .indonesian: "Latar Belakang", .japanese: "背景色",
            .korean: "배경색", .chineseSimplified: "背景色", .spanish: "Fondo"
        ],
        "studio.color.border": [
            .english: "Border Line", .indonesian: "Garis Tepi", .japanese: "枠線色",
            .korean: "테두리선", .chineseSimplified: "边框色", .spanish: "Borde"
        ],
        "studio.color.main": [
            .english: "Lead Vocal", .indonesian: "Vokal Utama", .japanese: "メイン歌詞",
            .korean: "메인 보컬", .chineseSimplified: "主唱歌词", .spanish: "Voz Principal"
        ],
        "studio.color.backing": [
            .english: "Backing Vocal", .indonesian: "Backing Vocal", .japanese: "バックコーラス",
            .korean: "백 보컬", .chineseSimplified: "和声歌词", .spanish: "Coros"
        ],
        "studio.color.upcoming": [
            .english: "Upcoming Text", .indonesian: "Teks Berikutnya", .japanese: "未歌唱テキスト",
            .korean: "다음 가사 텍스트", .chineseSimplified: "未唱文字", .spanish: "Texto Siguiente"
        ],
        "studio.color.accent": [
            .english: "Accent & Glow", .indonesian: "Aksen & Sorotan", .japanese: "アクセント発光",
            .korean: "강조 및 하이라이트", .chineseSimplified: "强调与高亮", .spanish: "Acento y Resalte"
        ],
        "studio.color.track": [
            .english: "Track Title", .indonesian: "Judul Lagu", .japanese: "曲タイトル",
            .korean: "곡 제목", .chineseSimplified: "曲目标题", .spanish: "Título de Pista"
        ],
        "studio.color.syncMode": [
            .english: "Artwork Color Sync", .indonesian: "Adaptasi Sampul", .japanese: "アートワーク同期",
            .korean: "앨범 아트 동기화", .chineseSimplified: "封面取色模式", .spanish: "Adaptar Carátula"
        ],
        "studio.color.tip": [
            .english: "Tip: Select 'Custom Theme Colors Only' if you want your custom palette applied 100% unchanged across all songs.",
            .indonesian: "Tip: Pilih 'Warna Tema Kustom Saja' bila ingin warna kustom Anda dipakai 100% tetap di setiap lagu.",
            .japanese: "ヒント: すべての曲でカスタム配色を固定したい場合は「カスタムテーマ色のみ」を選択してください。",
            .korean: "팁: 모든 곡에서 사용자 지정 색상을 100% 유지하려면 '사용자 지정 테마색만'을 선택하세요.",
            .chineseSimplified: "提示: 如需在所有歌曲中固定自定义配色，请选择“仅使用自定义主题色”。",
            .spanish: "Consejo: Elige 'Solo Colores del Tema' para mantener tu paleta personalizada fija en todas las canciones."
        ],
        "studio.anim.lineTrans": [
            .english: "Line Transition Style:", .indonesian: "Transisi Pergantian Baris:", .japanese: "行切替トランジション:",
            .korean: "줄 전환 효과:", .chineseSimplified: "歌词切行过渡:", .spanish: "Transición de Línea:"
        ],
        "studio.anim.wordAnim": [
            .english: "Per-Word / Letter Effect:", .indonesian: "Efek Gerak Per Kata / Huruf:", .japanese: "文字 / 単語アニメーション:",
            .korean: "단어 / 글자 효과:", .chineseSimplified: "逐词 / 逐字效果:", .spanish: "Efecto por Palabra / Letra:"
        ],
        "studio.anim.syncMode": [
            .english: "Vocal Auto-Sync Mode:", .indonesian: "Mode Auto-Sync Vokal:", .japanese: "音声自動同期モード:",
            .korean: "보컬 자동 동기화 모드:", .chineseSimplified: "人声自动同步模式:", .spanish: "Modo Auto-Sync Vocal:"
        ],
        "studio.anim.wordSpeed": [
            .english: "Word Sweep Speed:", .indonesian: "Kecepatan Gerak Kata:", .japanese: "文字スイープ速度:",
            .korean: "단어 진행 속도:", .chineseSimplified: "逐字扫光速度:", .spanish: "Velocidad por Palabra:"
        ],
        "studio.anim.karaokeOffset": [
            .english: "Shift Karaoke Timing:", .indonesian: "Geser Timing Karaoke:", .japanese: "カラオケタイミング調整:",
            .korean: "가라오케 타이밍 이동:", .chineseSimplified: "卡拉OK整体偏移:", .spanish: "Desplazar Tiempo Karaoke:"
        ],
        "studio.anim.backingOffset": [
            .english: "Backing Vocal Offset:", .indonesian: "Offset Back Vocal:", .japanese: "コーラス同期オフセット:",
            .korean: "백 보컬 오프셋:", .chineseSimplified: "和声偏移调整:", .spanish: "Compensación Coros:"
        ],
        "studio.anim.animSpeed": [
            .english: "Line Transition Speed:", .indonesian: "Kecepatan Transisi Baris:", .japanese: "行切替スピード:",
            .korean: "줄 전환 속도:", .chineseSimplified: "切行动画速度:", .spanish: "Velocidad de Transición:"
        ],
        "studio.anim.quickLabel": [
            .english: "Nudge:", .indonesian: "Cepat:", .japanese: "微調整:",
            .korean: "미세조정:", .chineseSimplified: "微调:", .spanish: "Ajuste:"
        ],
        "studio.anim.tempoLabel": [
            .english: "Pace:", .indonesian: "Tempo:", .japanese: "速度:",
            .korean: "속도:", .chineseSimplified: "速度:", .spanish: "Ritmo:"
        ],
        "studio.anim.resetTempo": [
            .english: "Reset Tempo & Offset (1.00x / 0.00s)", .indonesian: "Reset Tempo & Offset (1.00x / 0.00s)", .japanese: "速度とオフセットをリセット (1.00x / 0.00s)",
            .korean: "템포 및 오프셋 초기화 (1.00x / 0.00s)", .chineseSimplified: "重置速度与偏移 (1.00x / 0.00s)", .spanish: "Restablecer Ritmo (1.00x / 0.00s)"
        ],
        "studio.anim.recalibrateSync": [
            .english: "Recalibrate Auto-Sync", .indonesian: "Kalibrasi Auto-Sync Ulang", .japanese: "自動同期を再較正",
            .korean: "자동 동기화 재보정", .chineseSimplified: "重新校准自动同步", .spanish: "Recalibrar Auto-Sync"
        ],
        "studio.anim.note": [
            .english: "Use Stable (Crowded Vocals) for busy choruses, Backing Vocal Offset (-1.50s..+1.50s) to align harmonies, Word Speed (0.40x-2.20x), and Shift Timing (-2.50s..+2.50s).",
            .indonesian: "Gunakan Stabil (Chorus) bila vokal ramai, Offset Back Vocal (-1.50s..+1.50s) agar harmoni masuk pas, Kecepatan Kata (0.40x-2.20x), dan Geser Timing (-2.50s..+2.50s).",
            .korean: "보컬이 밀집된 코러스에는 '안정' 모드를 사용하고, 백 보컬 오프셋(-1.50s..+1.50s), 단어 속도(0.40x-2.20x), 타이밍 이동(-2.50s..+2.50s)으로 세밀하게 맞추세요.",
            .japanese: "合唱やサビが多い曲は「安定」モードを、ハモりのズレはコーラスオフセット(-1.50s〜+1.50s)、文字速度(0.40x-2.20x)、タイミング調整(-2.50s〜+2.50s)をご活用ください。",
            .chineseSimplified: "副歌密集时建议开启“稳定”模式；和声对齐可用和声偏移 (-1.50s..+1.50s)，字速 (0.40x-2.20x) 与整体偏移 (-2.50s..+2.50s) 可随时微调。",
            .spanish: "Usa 'Estable' en coros densos, Compensación de Coros (-1.50s..+1.50s) para armonías, Velocidad (0.40x-2.20x) y Desplazar Tiempo (-2.50s..+2.50s)."
        ],
        "studio.contrast.pass": [
            .english: "WCAG AA Pass", .indonesian: "WCAG AA Lolos", .japanese: "WCAG AA 合格",
            .korean: "WCAG AA 통과", .chineseSimplified: "WCAG AA 达标", .spanish: "Cumple WCAG AA"
        ],
        "studio.contrast.fail": [
            .english: "Low contrast (< 4.5:1)", .indonesian: "Kontras rendah (< 4.5:1)", .japanese: "コントラスト不足 (< 4.5:1)",
            .korean: "대비 낮음 (< 4.5:1)", .chineseSimplified: "对比度偏低 (< 4.5:1)", .spanish: "Bajo contraste (< 4.5:1)"
        ],
        "studio.contrast.summary": [
            .english: "Contrast Lead: %.1f:1 | Backing: %.1f:1 (%@)",
            .indonesian: "Kontras Main: %.1f:1 | Back Vocal: %.1f:1 (%@)",
            .japanese: "コントラスト メイン: %.1f:1 | コーラス: %.1f:1 (%@)",
            .korean: "명암비 메인: %.1f:1 | 백 보컬: %.1f:1 (%@)",
            .chineseSimplified: "对比度 主唱: %.1f:1 | 和声: %.1f:1 (%@)",
            .spanish: "Contraste Voz: %.1f:1 | Coros: %.1f:1 (%@)"
        ]
    ]
}
