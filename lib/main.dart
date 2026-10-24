import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  await AppController.instance.init();
  runApp(const MyNotesApp());
}

// ==========================================
// 1. نماذج البيانات (DATA MODELS)
// ==========================================

class Note {
  String id;
  String title;
  String content;
  DateTime date;
  bool isLocked;
  int colorValue;
  String? imagePath;
  String category;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
    this.isLocked = false,
    this.colorValue = 0xFF1E2235,
    this.imagePath,
    this.category = 'عام',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'content': content,
        'date': date.toIso8601String(),
        'isLocked': isLocked,
        'colorValue': colorValue,
        'imagePath': imagePath,
        'category': category,
      };

  factory Note.fromMap(Map<String, dynamic> map) => Note(
        id: map['id'],
        title: map['title'] ?? '',
        content: map['content'] ?? '',
        date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
        isLocked: map['isLocked'] ?? false,
        colorValue: map['colorValue'] ?? 0xFF1E2235,
        imagePath: map['imagePath'],
        category: map['category'] ?? 'عام',
      );
}

class TaskItem {
  String id;
  String title;
  bool isDone;
  String priority; // منخفض, متوسط, عاجل
  DateTime? dueDate;

  TaskItem({
    required this.id,
    required this.title,
    this.isDone = false,
    this.priority = 'متوسط',
    this.dueDate,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'isDone': isDone,
        'priority': priority,
        'dueDate': dueDate?.toIso8601String(),
      };

  factory TaskItem.fromMap(Map<String, dynamic> map) => TaskItem(
        id: map['id'],
        title: map['title'] ?? '',
        isDone: map['isDone'] ?? false,
        priority: map['priority'] ?? 'متوسط',
        dueDate: map['dueDate'] != null ? DateTime.tryParse(map['dueDate']) : null,
      );
}

// ==========================================
// 2. إدارة الحالة والتخزين (APP CONTROLLER)
// ==========================================

class AppController extends ChangeNotifier {
  static final AppController instance = AppController._internal();
  AppController._internal();

  late SharedPreferences _prefs;
  List<Note> notes = [];
  List<TaskItem> tasks = [];
  String googleApiKey = '';
  String googleSearchCx = '';
  String? appCustomBackground;
  ThemeMode themeMode = ThemeMode.dark;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    
    // تحميل المذكرات
    final notesRaw = _prefs.getString('saved_notes');
    if (notesRaw != null) {
      final List decoded = jsonDecode(notesRaw);
      notes = decoded.map((e) => Note.fromMap(e)).toList();
    }

    // تحميل المهام
    final tasksRaw = _prefs.getString('saved_tasks');
    if (tasksRaw != null) {
      final List decoded = jsonDecode(tasksRaw);
      tasks = decoded.map((e) => TaskItem.fromMap(e)).toList();
    }

    // الإعدادات
    googleApiKey = _prefs.getString('google_api_key') ?? '';
    googleSearchCx = _prefs.getString('google_search_cx') ?? '';
    appCustomBackground = _prefs.getString('app_background');
    final isDark = _prefs.getBool('is_dark_theme') ?? true;
    themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  // عمليات المذكرات
  Future<void> saveNote(Note note) async {
    final index = notes.indexWhere((n) => n.id == note.id);
    if (index >= 0) {
      notes[index] = note;
    } else {
      notes.insert(0, note);
    }
    await _syncNotes();
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    notes.removeWhere((n) => n.id == id);
    await _syncNotes();
    notifyListeners();
  }

  Future<void> _syncNotes() async {
    final encoded = jsonEncode(notes.map((n) => n.toMap()).toList());
    await _prefs.setString('saved_notes', encoded);
  }

  // عمليات المهام
  Future<void> saveTask(TaskItem task) async {
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      tasks[index] = task;
    } else {
      tasks.insert(0, task);
    }
    await _syncTasks();
    notifyListeners();
  }

  Future<void> toggleTask(String id) async {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index >= 0) {
      tasks[index].isDone = !tasks[index].isDone;
      await _syncTasks();
      notifyListeners();
    }
  }

  Future<void> deleteTask(String id) async {
    tasks.removeWhere((t) => t.id == id);
    await _syncTasks();
    notifyListeners();
  }

  Future<void> _syncTasks() async {
    final encoded = jsonEncode(tasks.map((t) => t.toMap()).toList());
    await _prefs.setString('saved_tasks', encoded);
  }

  // الإعدادات
  Future<void> updateGoogleApiConfig(String key, String cx) async {
    googleApiKey = key.trim();
    googleSearchCx = cx.trim();
    await _prefs.setString('google_api_key', googleApiKey);
    await _prefs.setString('google_search_cx', googleSearchCx);
    notifyListeners();
  }

  Future<void> setAppBackground(String? path) async {
    appCustomBackground = path;
    if (path == null) {
      await _prefs.remove('app_background');
    } else {
      await _prefs.setString('app_background', path);
    }
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDark) async {
    themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    await _prefs.setBool('is_dark_theme', isDark);
    notifyListeners();
  }
}

// ==========================================
// 3. خدمة الأمان والحماية (SECURITY SERVICE)
// ==========================================

class SecurityService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// التحقق مما إذا كان الجهاز يمتلك قفل أمان (بصمة / نمط / PIN / وجه)
  static Future<bool> isDeviceSecurityAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (_) {
      return false;
    }
  }

  /// طلب مصادقة أمان الجهاز (سواء بصمة أو نمط أو رمز المرور)
  static Future<bool> authenticate({required String localizedReason}) async {
    try {
      final isAvailable = await isDeviceSecurityAvailable();
      if (!isAvailable) {
        return false;
      }

      return await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // يتيح النمط، الرمز، والبصمة
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('Security Error: $e');
      return false;
    }
  }
}

// ==========================================
// 4. التطبيق والواجهات الأساسية
// ==========================================

class MyNotesApp extends StatelessWidget {
  const MyNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'مذكراتي',
          debugShowCheckedModeBanner: false,
          themeMode: AppController.instance.themeMode,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: const Color(0xFF6366F1),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            fontFamily: 'sans-serif',
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xFF6366F1),
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            cardColor: const Color(0xFF1E293B),
            fontFamily: 'sans-serif',
          ),
          home: const MainNavigationScreen(),
        );
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    NotesHomeScreen(),
    TasksScreen(),
    GoogleSearchScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final bgPath = AppController.instance.appCustomBackground;

    return Container(
      decoration: BoxDecoration(
        image: bgPath != null && File(bgPath).existsSync()
            ? DecorationImage(
                image: FileImage(File(bgPath)),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.85),
                  BlendMode.darken,
                ),
              )
            : null,
      ),
      child: Scaffold(
        backgroundColor: bgPath != null ? Colors.transparent : null,
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          elevation: 10,
          backgroundColor: Theme.of(context).cardColor.withOpacity(0.95),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.note_alt_outlined),
              selectedIcon: Icon(Icons.note_alt, color: Color(0xFF6366F1)),
              label: 'مذكراتي',
            ),
            NavigationDestination(
              icon: Icon(Icons.check_circle_outline),
              selectedIcon: Icon(Icons.check_circle, color: Color(0xFF6366F1)),
              label: 'المهام',
            ),
            NavigationDestination(
              icon: Icon(Icons.travel_explore_outlined),
              selectedIcon: Icon(Icons.travel_explore, color: Color(0xFF6366F1)),
              label: 'بحث جوجل',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings, color: Color(0xFF6366F1)),
              label: 'الإعدادات',
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. واجهة المذكرات (NOTES SCREEN)
// ==========================================

class NotesHomeScreen extends StatefulWidget {
  const NotesHomeScreen({super.key});

  @override
  State<NotesHomeScreen> createState() => _NotesHomeScreenState();
}

class _NotesHomeScreenState extends State<NotesHomeScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'الكل';

  final List<String> _categories = ['الكل', 'عام', 'شخصي', 'عمل', 'أفكار', 'مهم'];

  @override
  Widget build(BuildContext context) {
    final notes = AppController.instance.notes.where((note) {
      final matchesQuery = note.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          note.content.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == 'الكل' || note.category == _selectedCategory;
      return matchesQuery && matchesCategory;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('مذكراتي الاحترافية', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'إحصائيات المذكرات',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => _showStatsDialog(context),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('مذكرة جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
          );
        },
      ),
      body: Column(
        children: [
          // شريط البحث المتقدم
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'ابحث في محتوى وعناوين المذكرات...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // شريط الفئات
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = cat == _selectedCategory;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: const Color(0xFF6366F1),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : null,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (val) => setState(() => _selectedCategory = cat),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // قائمة المذكرات
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.description_outlined, size: 80, color: Colors.grey.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        const Text('لا توجد مذكرات حالياً، اضغط على زر الإضافة للبدء!',
                            style: TextStyle(color: Colors.grey, fontSize: 15)),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: notes.length,
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      return NoteGridCard(
                        note: note,
                        onTap: () => _openNoteSafely(context, note),
                        onDelete: () => AppController.instance.deleteNote(note.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openNoteSafely(BuildContext context, Note note) async {
    if (note.isLocked) {
      final authenticated = await SecurityService.authenticate(
        localizedReason: 'قم بالتحقق من هويتك (بصمة / نمط / رمز) لفتح المذكرة المحمية: "${note.title}"',
      );
      if (!authenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل التحقق من أمان الجهاز! تم منع فتح المذكرة.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(noteToEdit: note)),
    );
  }

  void _showStatsDialog(BuildContext context) {
    final notes = AppController.instance.notes;
    final locked = notes.where((n) => n.isLocked).length;
    final tasks = AppController.instance.tasks;
    final doneTasks = tasks.where((t) => t.isDone).length;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إحصائيات تطبيق مذكراتي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.note_alt, color: Colors.blue),
              title: const Text('إجمالي المذكرات'),
              trailing: Text('${notes.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.lock, color: Colors.amber),
              title: const Text('المذكرات المحمية بالأمان'),
              trailing: Text('$locked', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('المهام المنجزة'),
              trailing: Text('$doneTasks من ${tasks.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))
        ],
      ),
    );
  }
}

class NoteGridCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const NoteGridCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd');

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Color(note.colorValue),
            image: note.imagePath != null && File(note.imagePath!).existsSync()
                ? DecorationImage(
                    image: FileImage(File(note.imagePath!)),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.55),
                      BlendMode.darken,
                    ),
                  )
                : null,
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      note.category,
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ),
                  if (note.isLocked)
                    const Icon(Icons.lock, color: Colors.amberAccent, size: 20)
                ],
              ),
              const SizedBox(height: 10),
              Text(
                note.title.isEmpty ? 'بدون عنوان' : note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: note.isLocked
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.fingerprint_rounded, color: Colors.white54, size: 36),
                            SizedBox(height: 4),
                            Text('محتوى مشفر ومحمي', style: TextStyle(color: Colors.white60, fontSize: 11)),
                          ],
                        ),
                      )
                    : Text(
                        note.content,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                      ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateFormat.format(note.date),
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('حذف المذكرة'),
                          content: const Text('هل أنت متأكد من رغبتك في حذف هذه المذكرة نهائياً؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                onDelete();
                              },
                              child: const Text('حذف', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Icon(Icons.delete_outline, size: 18, color: Colors.white60),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 6. شاشة تحرير المذكرة والصوت والخلفيات
// ==========================================

class NoteEditorScreen extends StatefulWidget {
  final Note? noteToEdit;
  final String? initialContent;

  const NoteEditorScreen({super.key, this.noteToEdit, this.initialContent});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late bool _isLocked;
  late int _selectedColor;
  String? _noteImagePath;
  String _category = 'عام';

  // الصوت إلى نص
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  final List<int> _presetColors = [
    0xFF1E2235, // ليلي احترافي
    0xFF1E293B, // رمادي أزرق
    0xFF14532D, // زمردي داكن
    0xFF4C1D95, // أرجواني ملكي
    0xFF831843, // وردي عميق
    0xFF7C2D12, // نحاسي / طوبي
    0xFF0F172A, // أسود هادئ
  ];

  @override
  void initState() {
    super.initState();
    final n = widget.noteToEdit;
    _titleController = TextEditingController(text: n?.title ?? '');
    _contentController = TextEditingController(text: n?.content ?? widget.initialContent ?? '');
    _isLocked = n?.isLocked ?? false;
    _selectedColor = n?.colorValue ?? _presetColors.first;
    _noteImagePath = n?.imagePath;
    _category = n?.category ?? 'عام';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ميزة تحويل الصوت إلى نص
  void _toggleListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (errorNotification) {
          setState(() => _isListening = false);
        },
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          localeId: 'ar_SA', // اللغة العربية
          onResult: (result) {
            setState(() {
              _contentController.text = '${_contentController.text} ${result.recognizedWords}'.trim();
            });
          },
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('خدمة تحويل الصوت غير مدعومة أو لم يتم منح الإذن!')),
          );
        }
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  // تفعيل / إلغاء القفل باستخدام حماية الجهاز
  void _toggleLock() async {
    final isDeviceProtected = await SecurityService.isDeviceSecurityAvailable();
    if (!isDeviceProtected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تنبيه: قفل شاشة الهاتف غير مفعل! يرجى ضبط قفل شاشة (بصمة أو نمط أو رمز) في إعدادات الهاتف أولاً.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
      return;
    }

    final success = await SecurityService.authenticate(
      localizedReason: 'يرجى تأكيد هويتك لتفعيل أو تعديل حماية هذه المذكرة بقفل جهازك',
    );

    if (success) {
      setState(() {
        _isLocked = !_isLocked;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isLocked ? 'تم قفل المذكرة بأمان جهازك بنجاح!' : 'تم إلغاء قفل المذكرة.'),
            backgroundColor: _isLocked ? Colors.green : Colors.grey,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشلت المصادقة! لم يتم تغيير حالة القفل.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // اختيار صورة خلفية للمذكرة من المعرض
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (pickedFile != null) {
      setState(() {
        _noteImagePath = pickedFile.path;
      });
    }
  }

  void _save() {
    if (_titleController.text.trim().isEmpty && _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن حفظ مذكرة فارغة!')),
      );
      return;
    }

    final note = Note(
      id: widget.noteToEdit?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      date: DateTime.now(),
      isLocked: _isLocked,
      colorValue: _selectedColor,
      imagePath: _noteImagePath,
      category: _category,
    );

    AppController.instance.saveNote(note);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Color(_selectedColor),
        image: _noteImagePath != null && File(_noteImagePath!).existsSync()
            ? DecorationImage(
                image: FileImage(File(_noteImagePath!)),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.65),
                  BlendMode.darken,
                ),
              )
            : null,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            // زر قفل الجهاز
            IconButton(
              tooltip: 'حماية المذكرة بقفل الجهاز',
              icon: Icon(
                _isLocked ? Icons.lock : Icons.lock_open_rounded,
                color: _isLocked ? Colors.amberAccent : Colors.white70,
              ),
              onPressed: _toggleLock,
            ),
            // زر الصوت إلى نص
            IconButton(
              tooltip: 'الكتابة بالصوت',
              icon: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? Colors.redAccent : Colors.white70,
              ),
              onPressed: _toggleListening,
            ),
            // زر خلفية الصورة
            IconButton(
              tooltip: 'اختيار صورة خلفية للمذكرة',
              icon: const Icon(Icons.image_outlined),
              onPressed: _pickImage,
            ),
            // زر الألوان
            IconButton(
              tooltip: 'تغيير لون المذكرة',
              icon: const Icon(Icons.palette_outlined),
              onPressed: _showColorPicker,
            ),
            // زر الحفظ
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                onPressed: _save,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('حفظ'),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Column(
            children: [
              if (_isListening)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.record_voice_over, color: Colors.redAccent, size: 20),
                      SizedBox(width: 8),
                      Text('جارٍ الاستماع إليك باللغة العربية... تحدث الآن',
                          style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ],
                  ),
                ),

              // اختيار التصنيف
              DropdownButton<String>(
                value: _category,
                underline: const SizedBox(),
                dropdownColor: Theme.of(context).cardColor,
                items: ['عام', 'شخصي', 'عمل', 'أفكار', 'مهم']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _category = val);
                },
              ),

              // حقل العنوان
              TextField(
                controller: _titleController,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'عنوان المذكرة...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 24, fontWeight: FontWeight.bold),
                  border: InputBorder.none,
                ),
              ),
              const Divider(color: Colors.white12),

              // حقل المحتوى
              Expanded(
                child: TextField(
                  controller: _contentController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(fontSize: 17, height: 1.5, color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'ابدأ بكتابة أفكارك هنا، أو اضغط على أيقونة الميكروفون للكتابة بصوتك...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('اختر لون المذكرة:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _presetColors.map((colorVal) {
                  final isSelected = _selectedColor == colorVal;
                  return InkWell(
                    onTap: () {
                      setState(() => _selectedColor = colorVal);
                      Navigator.pop(context);
                    },
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(colorVal),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  );
                }).toList(),
              ),
              if (_noteImagePath != null) ...[
                const SizedBox(height: 15),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('إزالة الصورة المخصصة للمذكرة'),
                  onTap: () {
                    setState(() => _noteImagePath = null);
                    Navigator.pop(context);
                  },
                )
              ]
            ],
          ),
        );
      },
    );
  }
}

// ==========================================
// 7. قسم إدارة المهام (TASKS SCREEN)
// ==========================================

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final TextEditingController _taskController = TextEditingController();
  String _selectedPriority = 'متوسط';
  DateTime? _selectedDate;

  void _openAddTaskSheet() {
    _taskController.clear();
    _selectedPriority = 'متوسط';
    _selectedDate = null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مهمة جديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _taskController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'ما الذي تخطط لإنجازه اليوم؟',
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('الأولوية: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _selectedPriority,
                        items: ['عاجل', 'متوسط', 'منخفض']
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setSheetState(() => _selectedPriority = val);
                        },
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(_selectedDate == null ? 'تاريخ الاستحقاق' : DateFormat('MM/dd').format(_selectedDate!)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setSheetState(() => _selectedDate = picked);
                          }
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                      onPressed: () {
                        if (_taskController.text.trim().isEmpty) return;
                        final task = TaskItem(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          title: _taskController.text.trim(),
                          priority: _selectedPriority,
                          dueDate: _selectedDate,
                        );
                        AppController.instance.saveTask(task);
                        Navigator.pop(ctx);
                      },
                      child: const Text('إضافة المهمة الآن', style: TextStyle(fontSize: 16)),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = AppController.instance.tasks;
    final completedCount = tasks.where((t) => t.isDone).length;
    final progress = tasks.isEmpty ? 0.0 : (completedCount / tasks.length);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('إدارة المهام والإنجازات', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_task),
        label: const Text('مهمة جديدة'),
        onPressed: _openAddTaskSheet,
      ),
      body: Column(
        children: [
          // لوحة تقدم الإنجاز
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('مستوى إنجاز المهام اليوم',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${(progress * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
                  ),
                ),
                const SizedBox(height: 8),
                Text('تم إنهاء $completedCount من أصل ${tasks.length} مهام',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),

          // قائمة المهام
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.checklist_rounded, size: 70, color: Colors.grey.withOpacity(0.5)),
                        const SizedBox(height: 10),
                        const Text('لا توجد مهام حالياً، سجل أهدافك ومهامك اليوم!', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final item = tasks[index];
                      Color priorityColor = Colors.grey;
                      if (item.priority == 'عاجل') priorityColor = Colors.redAccent;
                      if (item.priority == 'متوسط') priorityColor = Colors.amber;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: Checkbox(
                            value: item.isDone,
                            activeColor: const Color(0xFF6366F1),
                            onChanged: (_) => AppController.instance.toggleTask(item.id),
                          ),
                          title: Text(
                            item.title,
                            style: TextStyle(
                              decoration: item.isDone ? TextDecoration.lineThrough : null,
                              color: item.isDone ? Colors.grey : null,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: priorityColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(item.priority, style: TextStyle(color: priorityColor, fontSize: 11)),
                              ),
                              if (item.dueDate != null) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.event, size: 14, color: Colors.grey.shade400),
                                const SizedBox(width: 4),
                                Text(DateFormat('yyyy/MM/dd').format(item.dueDate!),
                                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ]
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                            onPressed: () => AppController.instance.deleteTask(item.id),
                          ),
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// 8. قسم بحث جوجل الذكي (GOOGLE SEARCH ENGINE)
// ==========================================

class GoogleSearchScreen extends StatefulWidget {
  const GoogleSearchScreen({super.key});

  @override
  State<GoogleSearchScreen> createState() => _GoogleSearchScreenState();
}

class _GoogleSearchScreenState extends State<GoogleSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _performGoogleSearch() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    final apiKey = AppController.instance.googleApiKey;
    final cx = AppController.instance.googleSearchCx;

    if (apiKey.isEmpty || cx.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال Google API Key ومعرف محرك البحث (CX) في صفحة الإعدادات أولاً لتفعيل محرك البحث الحقيقي المباشر.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse(
        'https://www.googleapis.com/customsearch/v1?key=$apiKey&cx=$cx&q=${Uri.encodeComponent(query)}',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _searchResults = data['items'] ?? [];
          if (_searchResults.isEmpty) {
            _errorMessage = 'لم يتم العثور على أي نتائج لهذا البحث.';
          }
        });
      } else {
        setState(() {
          _errorMessage = 'خطأ من Google API: (${response.statusCode}) تأكد من صحة المفتاح والصلاحيات.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء الاتصال: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('محرك بحث جوجل المتكامل', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // شريط البحث
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    onSubmitted: (_) => _performGoogleSearch(),
                    decoration: InputDecoration(
                      hintText: 'ابحث في جوجل عن معلومة أو نص لإضافته...',
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF6366F1)),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                  icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                  onPressed: _performGoogleSearch,
                ),
              ],
            ),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),

          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                color: Colors.amber.shade900.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amberAccent),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white))),
                    ],
                  ),
                ),
              ),
            ),

          // عرض نتائج جوجل
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final item = _searchResults[index];
                final title = item['title'] ?? '';
                final snippet = item['snippet'] ?? '';
                final link = item['link'] ?? '';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF818CF8))),
                        const SizedBox(height: 6),
                        Text(snippet, style: const TextStyle(fontSize: 13, height: 1.4)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(link, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.add_to_photos_rounded, size: 16),
                              label: const Text('حفظ كمذكرة'),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NoteEditorScreen(
                                      initialContent: '$title\n\n$snippet\n\nالمصدر: $link',
                                    ),
                                  ),
                                );
                              },
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// 9. قسم الإعدادات الكامل (SETTINGS SCREEN)
// ==========================================

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _cxController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiKeyController.text = AppController.instance.googleApiKey;
    _cxController.text = AppController.instance.googleSearchCx;
  }

  Future<void> _pickAppBackground() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      await AppController.instance.setAppBackground(picked.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppController.instance.themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('إعدادات التطبيق الشاملة', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // قسم المظهر والخلفيات
          _buildSectionHeader('المظهر والخلفيات'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: const Color(0xFF6366F1)),
                  title: const Text('الوضع الليلي الفاخر (Dark Mode)'),
                  value: isDark,
                  onChanged: (val) => AppController.instance.toggleTheme(val),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.wallpaper, color: Color(0xFF6366F1)),
                  title: const Text('اختيار خلفية للتطبيق بالكامل من هاتفك'),
                  subtitle: Text(AppController.instance.appCustomBackground != null ? 'تم تعيين خلفية مخصصة' : 'الافتراضي'),
                  trailing: AppController.instance.appCustomBackground != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.redAccent),
                          onPressed: () => AppController.instance.setAppBackground(null),
                        )
                      : const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _pickAppBackground,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // قسم الأمان والمصادقة
          _buildSectionHeader('حماية الجهاز والأمان'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.security, color: Colors.green),
              title: const Text('اختبار أمان قفل الشاشة والجهاز'),
              subtitle: const Text('فحص توافق البصمة، النمط، أو الرمز السري'),
              trailing: const Icon(Icons.fingerprint, color: Color(0xFF6366F1)),
              onTap: () async {
                final isAvailable = await SecurityService.isDeviceSecurityAvailable();
                if (!isAvailable) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تنبيه: هاتفك لا يحتوي على قفل شاشة مفعل (بصمة أو نمط أو رمز)!'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                  return;
                }
                final auth = await SecurityService.authenticate(
                  localizedReason: 'اختبار نجاح نظام أمان جهازك لحماية المذكرات',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(auth ? 'تم التحقق بنجاح! حماية هاتفك تعمل بكفاءة.' : 'فشلت عملية التحقق.'),
                      backgroundColor: auth ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 16),

          // ربط Google API
          _buildSectionHeader('ربط محرك بحث جوجل (API Key)'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اربط التطبيق بمفتاح Google Custom Search الرسمي للبحث عن المعلومات والصور:',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    decoration: InputDecoration(
                      labelText: 'Google API Key',
                      prefixIcon: const Icon(Icons.vpn_key),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cxController,
                    decoration: InputDecoration(
                      labelText: 'Search Engine ID (CX)',
                      prefixIcon: const Icon(Icons.tag),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                      icon: const Icon(Icons.save),
                      label: const Text('حفظ إعدادات جوجل'),
                      onPressed: () {
                        AppController.instance.updateGoogleApiConfig(
                          _apiKeyController.text,
                          _cxController.text,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم حفظ مفاتيح Google API بنجاح!')),
                        );
                      },
                    ),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // حول التطبيق
          Center(
            child: Column(
              children: const [
                Text('تطبيق مذكراتي - الإصدار الاحترافي 1.0', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                SizedBox(height: 4),
                Text('تطبيق آمن، مفتوح المصدر ومحمي بنظام الهاتف', style: TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, right: 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF818CF8))),
    );
  }
}