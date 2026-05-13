import 'package:flutter/foundation.dart';

/// Lightweight runtime i18n. Strings live in this file (no .arb codegen) and
/// the active locale is a [ValueNotifier] watched by the root MaterialApp, so
/// changing the locale rebuilds the whole tree and every `AppStrings.t(...)`
/// call returns the new translation immediately.
///
/// Falls back to English then French for missing keys, so partial translations
/// degrade gracefully instead of throwing.
abstract final class AppStrings {
  /// BCP-47 primary subtag of the active UI language. Defaults to `en`.
  static final ValueNotifier<String> currentBcp47 = ValueNotifier<String>('en');

  static void setFromCode(String bcp47) {
    final code = _normalize(bcp47);
    if (code.isEmpty) return;
    if (!_maps.containsKey(code)) return;
    if (code == currentBcp47.value) return;
    currentBcp47.value = code;
  }

  /// Translate by key. Supports simple `{var}` placeholder substitution.
  static String t(String key, {Map<String, String>? args}) {
    final code = currentBcp47.value;
    final raw = _maps[code]?[key] ?? _maps['en']?[key] ?? _maps['fr']?[key] ?? key;
    if (args == null || args.isEmpty) return raw;
    var out = raw;
    args.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }

  static String _normalize(String code) {
    final t = code.trim().toLowerCase();
    if (t.isEmpty) return '';
    return t.split('-').first;
  }

  static final Map<String, Map<String, String>> _maps = {
    'fr': _fr,
    'en': _en,
    'es': _es,
    'de': _de,
    'it': _it,
    'pt': _pt,
    'nl': _nl,
    'ar': _ar,
    'ru': _ru,
    'zh': _zh,
    'ja': _ja,
    'ko': _ko,
  };

  // ─── French ───────────────────────────────────────────────────────────────
  static const Map<String, String> _fr = {
    'nav_search': 'Recherche',
    'nav_call': 'Appel',
    'nav_chat': 'Chat',
    'nav_tab3': 'Onglet 3',
    'tab_placeholder_soon': 'Bientôt',

    'onb_welcome_title': 'Bienvenue',
    'onb_welcome_subtitle': "Dis-nous comment t'appeler dans les appels.",
    'onb_language_title': 'Ta langue',
    'onb_language_subtitle':
        "Choisis la langue que tu parles. La langue de l'autre est détectée automatiquement quand il rejoint l'appel.",
    'onb_first_name_label': 'Prénom',
    'onb_first_name_hint': 'ex. Alex',
    'onb_next': 'Suivant',
    'onb_back': 'Retour',
    'onb_finish': 'Commencer',
    'onb_save': 'Enregistrer',
    'onb_need_name': 'Entre ton prénom.',
    'onb_need_language': 'Choisis la langue que tu parles.',
    'onb_language_picker_label': 'La langue que tu parles',
    'onb_profile_title': 'Ton profil',
    'onb_translation_help':
        "En appel, on traduira automatiquement la voix de l'autre dans ta langue, et la tienne dans la sienne.",

    'join_title': 'Rejoindre une room',
    'join_desc':
        'Choisis un nom de room et partage-le avec une autre personne. Vous devez utiliser le même nom pour vous retrouver en 1-on-1.',
    'join_room_label': 'Nom de la room',
    'join_room_hint': 'ex. diner-avec-sam',
    'join_name_label': 'Ton prénom',
    'join_name_hint': 'Comme les autres te verront',
    'join_speak': 'Tu parles {lang}',
    'join_no_lang': 'Aucune langue choisie',
    'join_lang_subtitle': "La langue de l'autre est détectée automatiquement.",
    'join_edit_profile': 'Modifier ton profil',
    'join_error_room': 'Entre un nom de room (3+ caractères) et ton prénom.',
    'join_error_room_format':
        "Le nom de room doit faire 3 à 64 caractères : lettres, chiffres, _ et - uniquement (pas d'espace ni #). Exemple : diner-avec-sam",
    'join_error_lang': 'Choisis ta langue dans ton profil avant de rejoindre.',
    'join_button': "Démarrer l'appel",
    'join_header_title': 'Calls',
    'join_header_subtitle': 'LiveKit · 1-on-1',
    'join_header_token_server': 'Token server: {api}',
    'join_header_profile_tooltip': 'Ton profil',
  };

  // ─── English ──────────────────────────────────────────────────────────────
  static const Map<String, String> _en = {
    'nav_search': 'Search',
    'nav_call': 'Call',
    'nav_chat': 'Chat',
    'nav_tab3': 'Tab 3',
    'tab_placeholder_soon': 'Soon',

    'onb_welcome_title': 'Welcome',
    'onb_welcome_subtitle': 'Tell us how to call you in calls.',
    'onb_language_title': 'Your language',
    'onb_language_subtitle':
        "Pick the language you speak. The other person's language is detected automatically when they join the call.",
    'onb_first_name_label': 'First name',
    'onb_first_name_hint': 'e.g. Alex',
    'onb_next': 'Next',
    'onb_back': 'Back',
    'onb_finish': 'Get started',
    'onb_save': 'Save',
    'onb_need_name': 'Enter your first name.',
    'onb_need_language': 'Pick the language you speak.',
    'onb_language_picker_label': 'The language you speak',
    'onb_profile_title': 'Your profile',
    'onb_translation_help':
        "In a call, we'll automatically translate the other person's voice into your language and yours into theirs.",

    'join_title': 'Join a room',
    'join_desc':
        'Pick any room name and share it with one other person. Both of you must use the same name to connect 1-on-1.',
    'join_room_label': 'Room name',
    'join_room_hint': 'e.g. dinner-with-sam',
    'join_name_label': 'Your first name',
    'join_name_hint': 'As others will see you',
    'join_speak': 'You speak {lang}',
    'join_no_lang': 'No language selected',
    'join_lang_subtitle': "The other person's language is detected automatically.",
    'join_edit_profile': 'Edit your profile',
    'join_error_room': 'Enter a room name (3+ characters) and your first name.',
    'join_error_room_format':
        'Room name must be 3-64 characters: letters, numbers, _ and - only (no spaces or #). Example: dinner-with-sam',
    'join_error_lang': 'Choose your language in your profile before joining.',
    'join_button': 'Start the call',
    'join_header_title': 'Calls',
    'join_header_subtitle': 'LiveKit · 1-on-1',
    'join_header_token_server': 'Token server: {api}',
    'join_header_profile_tooltip': 'Your profile',
  };

  // ─── Spanish ──────────────────────────────────────────────────────────────
  static const Map<String, String> _es = {
    'nav_search': 'Buscar',
    'nav_call': 'Llamada',
    'nav_chat': 'Chat',
    'nav_tab3': 'Pestaña 3',
    'tab_placeholder_soon': 'Pronto',

    'onb_welcome_title': 'Bienvenido',
    'onb_welcome_subtitle': 'Dinos cómo llamarte en las llamadas.',
    'onb_language_title': 'Tu idioma',
    'onb_language_subtitle':
        'Elige el idioma que hablas. El idioma de la otra persona se detecta automáticamente cuando se une a la llamada.',
    'onb_first_name_label': 'Nombre',
    'onb_first_name_hint': 'ej. Alex',
    'onb_next': 'Siguiente',
    'onb_back': 'Atrás',
    'onb_finish': 'Empezar',
    'onb_save': 'Guardar',
    'onb_need_name': 'Introduce tu nombre.',
    'onb_need_language': 'Elige el idioma que hablas.',
    'onb_language_picker_label': 'El idioma que hablas',
    'onb_profile_title': 'Tu perfil',
    'onb_translation_help':
        'En una llamada, traduciremos automáticamente la voz de la otra persona a tu idioma y la tuya al suyo.',

    'join_title': 'Unirse a una sala',
    'join_desc':
        'Elige un nombre de sala y compártelo con otra persona. Ambos deben usar el mismo nombre para conectarse 1-a-1.',
    'join_room_label': 'Nombre de la sala',
    'join_room_hint': 'ej. cena-con-sam',
    'join_name_label': 'Tu nombre',
    'join_name_hint': 'Como los demás te verán',
    'join_speak': 'Hablas {lang}',
    'join_no_lang': 'Ningún idioma elegido',
    'join_lang_subtitle': 'El idioma de la otra persona se detecta automáticamente.',
    'join_edit_profile': 'Editar tu perfil',
    'join_error_room': 'Introduce un nombre de sala (3+ caracteres) y tu nombre.',
    'join_error_room_format':
        'El nombre de la sala debe tener 3-64 caracteres: solo letras, números, _ y - (sin espacios ni #). Ejemplo: cena-con-sam',
    'join_error_lang': 'Elige tu idioma en tu perfil antes de unirte.',
    'join_button': 'Iniciar la llamada',
    'join_header_title': 'Llamadas',
    'join_header_subtitle': 'LiveKit · 1-a-1',
    'join_header_token_server': 'Servidor de tokens: {api}',
    'join_header_profile_tooltip': 'Tu perfil',
  };

  // ─── German ───────────────────────────────────────────────────────────────
  static const Map<String, String> _de = {
    'nav_search': 'Suche',
    'nav_call': 'Anruf',
    'nav_chat': 'Chat',
    'nav_tab3': 'Tab 3',
    'tab_placeholder_soon': 'Bald',

    'onb_welcome_title': 'Willkommen',
    'onb_welcome_subtitle': 'Sag uns, wie wir dich in Anrufen nennen sollen.',
    'onb_language_title': 'Deine Sprache',
    'onb_language_subtitle':
        'Wähle die Sprache, die du sprichst. Die Sprache der anderen Person wird automatisch erkannt, wenn sie dem Anruf beitritt.',
    'onb_first_name_label': 'Vorname',
    'onb_first_name_hint': 'z.B. Alex',
    'onb_next': 'Weiter',
    'onb_back': 'Zurück',
    'onb_finish': 'Loslegen',
    'onb_save': 'Speichern',
    'onb_need_name': 'Gib deinen Vornamen ein.',
    'onb_need_language': 'Wähle die Sprache, die du sprichst.',
    'onb_language_picker_label': 'Die Sprache, die du sprichst',
    'onb_profile_title': 'Dein Profil',
    'onb_translation_help':
        'In einem Anruf übersetzen wir automatisch die Stimme der anderen Person in deine Sprache und deine in ihre.',

    'join_title': 'Einem Raum beitreten',
    'join_desc':
        'Wähle einen Raumnamen und teile ihn mit einer anderen Person. Ihr müsst beide denselben Namen verwenden, um euch 1-zu-1 zu verbinden.',
    'join_room_label': 'Raumname',
    'join_room_hint': 'z.B. abendessen-mit-sam',
    'join_name_label': 'Dein Vorname',
    'join_name_hint': 'Wie andere dich sehen',
    'join_speak': 'Du sprichst {lang}',
    'join_no_lang': 'Keine Sprache gewählt',
    'join_lang_subtitle': 'Die Sprache der anderen Person wird automatisch erkannt.',
    'join_edit_profile': 'Profil bearbeiten',
    'join_error_room': 'Gib einen Raumnamen (mindestens 3 Zeichen) und deinen Vornamen ein.',
    'join_error_room_format':
        'Der Raumname muss 3-64 Zeichen lang sein: nur Buchstaben, Zahlen, _ und - (keine Leerzeichen oder #). Beispiel: abendessen-mit-sam',
    'join_error_lang': 'Wähle deine Sprache im Profil, bevor du beitrittst.',
    'join_button': 'Anruf starten',
    'join_header_title': 'Anrufe',
    'join_header_subtitle': 'LiveKit · 1-zu-1',
    'join_header_token_server': 'Token-Server: {api}',
    'join_header_profile_tooltip': 'Dein Profil',
  };

  // ─── Italian ──────────────────────────────────────────────────────────────
  static const Map<String, String> _it = {
    'nav_search': 'Cerca',
    'nav_call': 'Chiamata',
    'nav_chat': 'Chat',
    'nav_tab3': 'Scheda 3',
    'tab_placeholder_soon': 'Presto',

    'onb_welcome_title': 'Benvenuto',
    'onb_welcome_subtitle': 'Dicci come chiamarti nelle chiamate.',
    'onb_language_title': 'La tua lingua',
    'onb_language_subtitle':
        "Scegli la lingua che parli. La lingua dell'altra persona viene rilevata automaticamente quando si unisce alla chiamata.",
    'onb_first_name_label': 'Nome',
    'onb_first_name_hint': 'es. Alex',
    'onb_next': 'Avanti',
    'onb_back': 'Indietro',
    'onb_finish': 'Inizia',
    'onb_save': 'Salva',
    'onb_need_name': 'Inserisci il tuo nome.',
    'onb_need_language': 'Scegli la lingua che parli.',
    'onb_language_picker_label': 'La lingua che parli',
    'onb_profile_title': 'Il tuo profilo',
    'onb_translation_help':
        "In una chiamata, tradurremo automaticamente la voce dell'altra persona nella tua lingua e la tua nella sua.",

    'join_title': 'Entra in una stanza',
    'join_desc':
        "Scegli un nome di stanza e condividilo con un'altra persona. Entrambi dovete usare lo stesso nome per collegarvi 1-a-1.",
    'join_room_label': 'Nome della stanza',
    'join_room_hint': 'es. cena-con-sam',
    'join_name_label': 'Il tuo nome',
    'join_name_hint': 'Come gli altri ti vedranno',
    'join_speak': 'Parli {lang}',
    'join_no_lang': 'Nessuna lingua scelta',
    'join_lang_subtitle': "La lingua dell'altra persona viene rilevata automaticamente.",
    'join_edit_profile': 'Modifica il tuo profilo',
    'join_error_room': 'Inserisci un nome di stanza (3+ caratteri) e il tuo nome.',
    'join_error_room_format':
        'Il nome della stanza deve avere 3-64 caratteri: solo lettere, numeri, _ e - (niente spazi né #). Esempio: cena-con-sam',
    'join_error_lang': 'Scegli la tua lingua nel profilo prima di entrare.',
    'join_button': 'Avvia la chiamata',
    'join_header_title': 'Chiamate',
    'join_header_subtitle': 'LiveKit · 1-a-1',
    'join_header_token_server': 'Token server: {api}',
    'join_header_profile_tooltip': 'Il tuo profilo',
  };

  // ─── Portuguese ───────────────────────────────────────────────────────────
  static const Map<String, String> _pt = {
    'nav_search': 'Pesquisa',
    'nav_call': 'Chamada',
    'nav_chat': 'Chat',
    'nav_tab3': 'Aba 3',
    'tab_placeholder_soon': 'Em breve',

    'onb_welcome_title': 'Bem-vindo',
    'onb_welcome_subtitle': 'Diz-nos como te chamar nas chamadas.',
    'onb_language_title': 'A tua língua',
    'onb_language_subtitle':
        'Escolhe a língua que falas. A língua da outra pessoa é detetada automaticamente quando entra na chamada.',
    'onb_first_name_label': 'Primeiro nome',
    'onb_first_name_hint': 'ex. Alex',
    'onb_next': 'Seguinte',
    'onb_back': 'Voltar',
    'onb_finish': 'Começar',
    'onb_save': 'Guardar',
    'onb_need_name': 'Insere o teu primeiro nome.',
    'onb_need_language': 'Escolhe a língua que falas.',
    'onb_language_picker_label': 'A língua que falas',
    'onb_profile_title': 'O teu perfil',
    'onb_translation_help':
        'Numa chamada, traduziremos automaticamente a voz da outra pessoa para a tua língua e a tua para a dela.',

    'join_title': 'Entrar numa sala',
    'join_desc':
        'Escolhe um nome de sala e partilha-o com outra pessoa. Ambos têm de usar o mesmo nome para se ligarem 1-para-1.',
    'join_room_label': 'Nome da sala',
    'join_room_hint': 'ex. jantar-com-sam',
    'join_name_label': 'O teu primeiro nome',
    'join_name_hint': 'Como os outros te verão',
    'join_speak': 'Falas {lang}',
    'join_no_lang': 'Nenhuma língua escolhida',
    'join_lang_subtitle': 'A língua da outra pessoa é detetada automaticamente.',
    'join_edit_profile': 'Editar o teu perfil',
    'join_error_room': 'Insere um nome de sala (3+ caracteres) e o teu nome.',
    'join_error_room_format':
        'O nome da sala deve ter 3-64 caracteres: apenas letras, números, _ e - (sem espaços ou #). Exemplo: jantar-com-sam',
    'join_error_lang': 'Escolhe a tua língua no perfil antes de entrares.',
    'join_button': 'Iniciar a chamada',
    'join_header_title': 'Chamadas',
    'join_header_subtitle': 'LiveKit · 1-para-1',
    'join_header_token_server': 'Servidor de tokens: {api}',
    'join_header_profile_tooltip': 'O teu perfil',
  };

  // ─── Dutch ────────────────────────────────────────────────────────────────
  static const Map<String, String> _nl = {
    'nav_search': 'Zoeken',
    'nav_call': 'Oproep',
    'nav_chat': 'Chat',
    'nav_tab3': 'Tabblad 3',
    'tab_placeholder_soon': 'Binnenkort',

    'onb_welcome_title': 'Welkom',
    'onb_welcome_subtitle': 'Vertel ons hoe we je in gesprekken kunnen noemen.',
    'onb_language_title': 'Jouw taal',
    'onb_language_subtitle':
        'Kies de taal die je spreekt. De taal van de andere persoon wordt automatisch gedetecteerd wanneer hij deelneemt aan het gesprek.',
    'onb_first_name_label': 'Voornaam',
    'onb_first_name_hint': 'bijv. Alex',
    'onb_next': 'Volgende',
    'onb_back': 'Terug',
    'onb_finish': 'Aan de slag',
    'onb_save': 'Opslaan',
    'onb_need_name': 'Voer je voornaam in.',
    'onb_need_language': 'Kies de taal die je spreekt.',
    'onb_language_picker_label': 'De taal die je spreekt',
    'onb_profile_title': 'Jouw profiel',
    'onb_translation_help':
        'In een gesprek vertalen we de stem van de andere persoon automatisch naar jouw taal en die van jou naar die van hen.',

    'join_title': 'Een kamer binnengaan',
    'join_desc':
        'Kies een kamernaam en deel deze met een andere persoon. Jullie moeten beiden dezelfde naam gebruiken om 1-op-1 te verbinden.',
    'join_room_label': 'Kamernaam',
    'join_room_hint': 'bijv. diner-met-sam',
    'join_name_label': 'Jouw voornaam',
    'join_name_hint': 'Hoe anderen je zullen zien',
    'join_speak': 'Je spreekt {lang}',
    'join_no_lang': 'Geen taal gekozen',
    'join_lang_subtitle': 'De taal van de andere persoon wordt automatisch gedetecteerd.',
    'join_edit_profile': 'Profiel bewerken',
    'join_error_room': 'Voer een kamernaam (3+ tekens) en je voornaam in.',
    'join_error_room_format':
        'Kamernaam moet 3-64 tekens lang zijn: alleen letters, cijfers, _ en - (geen spaties of #). Voorbeeld: diner-met-sam',
    'join_error_lang': 'Kies je taal in je profiel voordat je deelneemt.',
    'join_button': 'Oproep starten',
    'join_header_title': 'Oproepen',
    'join_header_subtitle': 'LiveKit · 1-op-1',
    'join_header_token_server': 'Token-server: {api}',
    'join_header_profile_tooltip': 'Jouw profiel',
  };

  // ─── Arabic ───────────────────────────────────────────────────────────────
  static const Map<String, String> _ar = {
    'nav_search': 'بحث',
    'nav_call': 'مكالمة',
    'nav_chat': 'دردشة',
    'nav_tab3': 'علامة التبويب 3',
    'tab_placeholder_soon': 'قريباً',

    'onb_welcome_title': 'مرحباً',
    'onb_welcome_subtitle': 'أخبرنا كيف نناديك في المكالمات.',
    'onb_language_title': 'لغتك',
    'onb_language_subtitle':
        'اختر اللغة التي تتحدثها. يتم اكتشاف لغة الشخص الآخر تلقائياً عند انضمامه إلى المكالمة.',
    'onb_first_name_label': 'الاسم الأول',
    'onb_first_name_hint': 'مثل أليكس',
    'onb_next': 'التالي',
    'onb_back': 'رجوع',
    'onb_finish': 'ابدأ',
    'onb_save': 'حفظ',
    'onb_need_name': 'أدخل اسمك الأول.',
    'onb_need_language': 'اختر اللغة التي تتحدثها.',
    'onb_language_picker_label': 'اللغة التي تتحدثها',
    'onb_profile_title': 'ملفك الشخصي',
    'onb_translation_help':
        'في المكالمة، سنترجم تلقائياً صوت الشخص الآخر إلى لغتك وصوتك إلى لغته.',

    'join_title': 'الانضمام إلى غرفة',
    'join_desc':
        'اختر اسم غرفة وشاركه مع شخص آخر. يجب أن يستخدم كلاكما الاسم نفسه للاتصال 1-إلى-1.',
    'join_room_label': 'اسم الغرفة',
    'join_room_hint': 'مثل dinner-with-sam',
    'join_name_label': 'اسمك الأول',
    'join_name_hint': 'كما سيراك الآخرون',
    'join_speak': 'تتحدث {lang}',
    'join_no_lang': 'لم يتم اختيار لغة',
    'join_lang_subtitle': 'يتم اكتشاف لغة الشخص الآخر تلقائياً.',
    'join_edit_profile': 'تعديل ملفك الشخصي',
    'join_error_room': 'أدخل اسم غرفة (3+ أحرف) واسمك الأول.',
    'join_error_room_format':
        'يجب أن يكون اسم الغرفة 3-64 حرفاً: حروف وأرقام و _ و - فقط (بدون مسافات أو #). مثال: dinner-with-sam',
    'join_error_lang': 'اختر لغتك في ملفك الشخصي قبل الانضمام.',
    'join_button': 'بدء المكالمة',
    'join_header_title': 'المكالمات',
    'join_header_subtitle': 'LiveKit · 1-إلى-1',
    'join_header_token_server': 'خادم التوكن: {api}',
    'join_header_profile_tooltip': 'ملفك الشخصي',
  };

  // ─── Russian ──────────────────────────────────────────────────────────────
  static const Map<String, String> _ru = {
    'nav_search': 'Поиск',
    'nav_call': 'Звонок',
    'nav_chat': 'Чат',
    'nav_tab3': 'Вкладка 3',
    'tab_placeholder_soon': 'Скоро',

    'onb_welcome_title': 'Добро пожаловать',
    'onb_welcome_subtitle': 'Скажи, как тебя называть в звонках.',
    'onb_language_title': 'Твой язык',
    'onb_language_subtitle':
        'Выбери язык, на котором ты говоришь. Язык собеседника определяется автоматически, когда он присоединяется к звонку.',
    'onb_first_name_label': 'Имя',
    'onb_first_name_hint': 'напр. Alex',
    'onb_next': 'Далее',
    'onb_back': 'Назад',
    'onb_finish': 'Начать',
    'onb_save': 'Сохранить',
    'onb_need_name': 'Введи своё имя.',
    'onb_need_language': 'Выбери язык, на котором ты говоришь.',
    'onb_language_picker_label': 'Язык, на котором ты говоришь',
    'onb_profile_title': 'Твой профиль',
    'onb_translation_help':
        'Во время звонка мы автоматически переведём голос собеседника на твой язык, а твой — на его.',

    'join_title': 'Войти в комнату',
    'join_desc':
        'Выбери название комнаты и поделись им с другим человеком. Вы оба должны использовать одно и то же название для связи 1-на-1.',
    'join_room_label': 'Название комнаты',
    'join_room_hint': 'напр. dinner-with-sam',
    'join_name_label': 'Твоё имя',
    'join_name_hint': 'Как тебя увидят другие',
    'join_speak': 'Ты говоришь на {lang}',
    'join_no_lang': 'Язык не выбран',
    'join_lang_subtitle': 'Язык собеседника определяется автоматически.',
    'join_edit_profile': 'Изменить профиль',
    'join_error_room': 'Введи название комнаты (3+ символа) и своё имя.',
    'join_error_room_format':
        'Название комнаты должно быть 3-64 символа: только буквы, цифры, _ и - (без пробелов и #). Пример: dinner-with-sam',
    'join_error_lang': 'Выбери язык в профиле перед подключением.',
    'join_button': 'Начать звонок',
    'join_header_title': 'Звонки',
    'join_header_subtitle': 'LiveKit · 1-на-1',
    'join_header_token_server': 'Сервер токенов: {api}',
    'join_header_profile_tooltip': 'Твой профиль',
  };

  // ─── Chinese (Simplified) ─────────────────────────────────────────────────
  static const Map<String, String> _zh = {
    'nav_search': '搜索',
    'nav_call': '通话',
    'nav_chat': '聊天',
    'nav_tab3': '标签 3',
    'tab_placeholder_soon': '即将推出',

    'onb_welcome_title': '欢迎',
    'onb_welcome_subtitle': '告诉我们在通话中如何称呼你。',
    'onb_language_title': '你的语言',
    'onb_language_subtitle':
        '选择你使用的语言。对方加入通话时，他们的语言会自动检测。',
    'onb_first_name_label': '名字',
    'onb_first_name_hint': '例如 Alex',
    'onb_next': '下一步',
    'onb_back': '返回',
    'onb_finish': '开始',
    'onb_save': '保存',
    'onb_need_name': '请输入你的名字。',
    'onb_need_language': '请选择你使用的语言。',
    'onb_language_picker_label': '你使用的语言',
    'onb_profile_title': '你的个人资料',
    'onb_translation_help':
        '在通话中，我们将自动把对方的声音翻译成你的语言，把你的声音翻译成对方的语言。',

    'join_title': '加入房间',
    'join_desc':
        '选择一个房间名称并与他人分享。你们必须使用相同的名称才能进行 1 对 1 连接。',
    'join_room_label': '房间名称',
    'join_room_hint': '例如 dinner-with-sam',
    'join_name_label': '你的名字',
    'join_name_hint': '其他人看到你的方式',
    'join_speak': '你说{lang}',
    'join_no_lang': '未选择语言',
    'join_lang_subtitle': '对方的语言会自动检测。',
    'join_edit_profile': '编辑你的个人资料',
    'join_error_room': '请输入房间名称（3+ 个字符）和你的名字。',
    'join_error_room_format':
        '房间名称必须为 3-64 个字符：仅限字母、数字、_ 和 -（不能有空格或 #）。例如：dinner-with-sam',
    'join_error_lang': '加入前请在个人资料中选择你的语言。',
    'join_button': '开始通话',
    'join_header_title': '通话',
    'join_header_subtitle': 'LiveKit · 1 对 1',
    'join_header_token_server': 'Token 服务器：{api}',
    'join_header_profile_tooltip': '你的个人资料',
  };

  // ─── Japanese ─────────────────────────────────────────────────────────────
  static const Map<String, String> _ja = {
    'nav_search': '検索',
    'nav_call': '通話',
    'nav_chat': 'チャット',
    'nav_tab3': 'タブ 3',
    'tab_placeholder_soon': '近日公開',

    'onb_welcome_title': 'ようこそ',
    'onb_welcome_subtitle': '通話で呼ばれる名前を教えてください。',
    'onb_language_title': 'あなたの言語',
    'onb_language_subtitle':
        '話す言語を選んでください。相手の言語は通話に参加したときに自動的に検出されます。',
    'onb_first_name_label': '名前',
    'onb_first_name_hint': '例: Alex',
    'onb_next': '次へ',
    'onb_back': '戻る',
    'onb_finish': '始める',
    'onb_save': '保存',
    'onb_need_name': '名前を入力してください。',
    'onb_need_language': '話す言語を選んでください。',
    'onb_language_picker_label': '話す言語',
    'onb_profile_title': 'プロフィール',
    'onb_translation_help':
        '通話中、相手の声をあなたの言語に、あなたの声を相手の言語に自動翻訳します。',

    'join_title': 'ルームに参加',
    'join_desc':
        'ルーム名を選んで、他の人と共有してください。1対1で接続するには、同じ名前を使う必要があります。',
    'join_room_label': 'ルーム名',
    'join_room_hint': '例: dinner-with-sam',
    'join_name_label': 'あなたの名前',
    'join_name_hint': '他の人に表示される名前',
    'join_speak': 'あなたは{lang}を話します',
    'join_no_lang': '言語が選択されていません',
    'join_lang_subtitle': '相手の言語は自動的に検出されます。',
    'join_edit_profile': 'プロフィールを編集',
    'join_error_room': 'ルーム名（3文字以上）とあなたの名前を入力してください。',
    'join_error_room_format':
        'ルーム名は3〜64文字: 英数字、_、- のみ（スペースや # は不可）。例: dinner-with-sam',
    'join_error_lang': '参加する前にプロフィールで言語を選んでください。',
    'join_button': '通話を開始',
    'join_header_title': '通話',
    'join_header_subtitle': 'LiveKit · 1対1',
    'join_header_token_server': 'トークンサーバー: {api}',
    'join_header_profile_tooltip': 'プロフィール',
  };

  // ─── Korean ───────────────────────────────────────────────────────────────
  static const Map<String, String> _ko = {
    'nav_search': '검색',
    'nav_call': '통화',
    'nav_chat': '채팅',
    'nav_tab3': '탭 3',
    'tab_placeholder_soon': '곧 출시',

    'onb_welcome_title': '환영합니다',
    'onb_welcome_subtitle': '통화에서 어떻게 부를지 알려주세요.',
    'onb_language_title': '당신의 언어',
    'onb_language_subtitle':
        '사용하는 언어를 선택하세요. 상대방의 언어는 통화에 참여할 때 자동으로 감지됩니다.',
    'onb_first_name_label': '이름',
    'onb_first_name_hint': '예: Alex',
    'onb_next': '다음',
    'onb_back': '뒤로',
    'onb_finish': '시작하기',
    'onb_save': '저장',
    'onb_need_name': '이름을 입력하세요.',
    'onb_need_language': '사용하는 언어를 선택하세요.',
    'onb_language_picker_label': '사용하는 언어',
    'onb_profile_title': '프로필',
    'onb_translation_help':
        '통화 중에 상대방의 음성을 당신의 언어로, 당신의 음성을 상대방의 언어로 자동 번역합니다.',

    'join_title': '방 참여하기',
    'join_desc':
        '방 이름을 선택하고 다른 사람과 공유하세요. 1대1로 연결하려면 같은 이름을 사용해야 합니다.',
    'join_room_label': '방 이름',
    'join_room_hint': '예: dinner-with-sam',
    'join_name_label': '당신의 이름',
    'join_name_hint': '다른 사람에게 보여질 이름',
    'join_speak': '{lang}를 사용합니다',
    'join_no_lang': '선택된 언어가 없습니다',
    'join_lang_subtitle': '상대방의 언어는 자동으로 감지됩니다.',
    'join_edit_profile': '프로필 편집',
    'join_error_room': '방 이름(3자 이상)과 이름을 입력하세요.',
    'join_error_room_format':
        '방 이름은 3-64자여야 합니다: 영문자, 숫자, _, -만 사용 (공백이나 # 불가). 예: dinner-with-sam',
    'join_error_lang': '참여하기 전에 프로필에서 언어를 선택하세요.',
    'join_button': '통화 시작',
    'join_header_title': '통화',
    'join_header_subtitle': 'LiveKit · 1대1',
    'join_header_token_server': '토큰 서버: {api}',
    'join_header_profile_tooltip': '프로필',
  };
}
