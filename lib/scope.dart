import 'package:flutter/material.dart';
import 'db.dart';
import 'target.dart';

/// Notifier pilihan outlet; [ping] memberi tahu pendengar walau teksnya sama
/// (dipakai saat yang berubah hanya pilihan kelompok).
class ScopeNotifier extends ValueNotifier<String> {
  ScopeNotifier(super.value);
  void ping() => notifyListeners();
}

/// Outlet atau kelompok yang sedang dipilih admin. Teks kosong ('') dan
/// kelompok 0 = semua outlet. Memilih kelompok menyaring data ke semua toko
/// di kelompok itu. Dibaca oleh semua halaman admin; saat pilihan berubah,
/// Shell memuat ulang halaman yang sedang terbuka.
class AdminScope {
  static final outlet = ScopeNotifier('');

  /// Kelompok yang dipilih (id outlet_groups), 0 = tidak memilih kelompok.
  static int groupId = 0;

  /// Dinaikkan setiap kali daftar outlet / kelompok berubah (tambah, hapus,
  /// pindah), supaya bilah pilihan outlet ikut memuat ulang.
  static final refresh = ValueNotifier<int>(0);

  static String get value => outlet.value;
  static bool get isAll => outlet.value.isEmpty;

  static void _set(String name, int gid) {
    final changed = outlet.value != name || groupId != gid;
    groupId = gid;
    if (outlet.value != name) {
      outlet.value = name; // memberi tahu pendengar
    } else if (changed) {
      outlet.ping();
    }
  }

  static void pick(String name) => _set(name, 0);
  static void pickGroup(int id) => _set('', id);
  static void reset() => _set('', 0);
  static void reloadOutlets() => refresh.value++;
}

/// Pembatas outlet untuk akun mitra. Mitra hanya melihat outlet miliknya
/// yang langganannya masih aktif;
/// akun lain (develop, admin, spv) tidak dibatasi. Dipakai semua query laporan
/// supaya "Semua Outlet" bagi mitra berarti "semua outlet milik mitra itu".
class Scope {
  /// Outlet milik mitra yang sedang login. null = tidak dibatasi.
  static List<String>? mine;
  static bool get restricted => mine != null;

  /// Kelompok yang boleh dilihat akun ini (hanya yang punya toko terlihat)
  /// dan daftar toko di tiap kelompok.
  static List<Rec> groups = [];
  static Map<int, List<String>> members = {};

  /// Nama kelompok yang sedang dipilih ('' = tidak memilih kelompok).
  static String get groupLabel {
    final id = AdminScope.groupId;
    if (id == 0) return '';
    for (final g in groups) {
      if (g['id'] == id) return g['name'] as String;
    }
    return '';
  }

  /// Muat daftar outlet yang boleh dilihat akun ini:
  /// - mitra: outlet miliknya yang langganannya masih aktif,
  /// - admin/spv dengan akses "outlet tertentu": outlet yang dipilih Develop,
  /// - develop dan admin/spv akses "semua outlet": tidak dibatasi (null).
  /// Sekalian memuat daftar kelompok untuk pilihan di bilah atas.
  static Future<void> load() async {
    final u = Session.user;
    if (u == null || !Session.isAdmin) {
      mine = null;
      groups = [];
      members = {};
      return;
    }
    await Db.ensureV3();
    if (Session.isDevelop) {
      mine = null;
    } else if (Session.isMitra) {
      // outlet yang langganannya habis tidak ikut tampil (terkunci)
      final r = await Db.q(
          'SELECT name, sub_required, sub_until FROM outlets WHERE owner_id=? ORDER BY name',
          [Session.id]);
      mine = [
        for (final o in r)
          if (outletSubLock(o) == null) o['name'] as String
      ];
    } else if (u['outlet_scope'] == 'custom') {
      final r = await Db.q(
          'SELECT a.outlet FROM account_outlets a JOIN outlets o ON o.name=a.outlet WHERE a.user_id=? ORDER BY a.outlet',
          [Session.id]);
      mine = [for (final o in r) o['outlet'] as String];
    } else {
      mine = null;
    }
    await _loadGroups();
  }

  static Future<void> _loadGroups() async {
    final g = await Db.q(
        "SELECT id, name, kind FROM outlet_groups ORDER BY CASE kind WHEN 'pusat' THEN 0 ELSE 1 END, name");
    final o = await Db.q(
        'SELECT name, group_id FROM outlets WHERE group_id IS NOT NULL ORDER BY name');
    final m = <int, List<String>>{};
    for (final r in o) {
      final n = r['name'] as String;
      if (mine == null || mine!.contains(n)) {
        m.putIfAbsent(r['group_id'] as int, () => []).add(n);
      }
    }
    members = m;
    groups = [
      for (final r in g)
        if (m.containsKey(r['id'])) r
    ];
  }

  static bool get _on =>
      restricted || !AdminScope.isAll || AdminScope.groupId != 0;

  /// Outlet yang dipakai untuk menyaring data saat ini.
  static List<String> get names {
    if (!AdminScope.isAll) {
      final m = mine;
      if (m == null || m.contains(AdminScope.value)) return [AdminScope.value];
      return m;
    }
    if (AdminScope.groupId != 0) {
      return members[AdminScope.groupId] ?? const [];
    }
    return mine ?? const [];
  }

  static String cond(String col) {
    final n = names;
    if (n.isEmpty) return '1=0';
    if (n.length == 1) return '$col=?';
    return '$col IN (${List.filled(n.length, '?').join(',')})';
  }

  /// Potongan SQL " AND kolom ..." (kosong kalau tanpa batasan).
  static String and(String col) => _on ? ' AND ${cond(col)}' : '';

  /// Potongan SQL "WHERE kolom ..." (kosong kalau tanpa batasan).
  static String where(String col) => _on ? 'WHERE ${cond(col)}' : '';

  static List<Object?> get args =>
      _on ? List<Object?>.of(names) : const <Object?>[];
}

/// Bilah pilihan outlet di bagian atas halaman admin.
class ScopeBar extends StatefulWidget {
  const ScopeBar({super.key});
  @override
  State<ScopeBar> createState() => _ScopeBarState();
}

class _ScopeBarState extends State<ScopeBar> {
  List<String> outlets = [];

  @override
  void initState() {
    super.initState();
    AdminScope.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AdminScope.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    await Scope.load();
    final v = await Target.outlets();
    if (!mounted) return;
    setState(() => outlets = v);
    // Outlet / kelompok yang dipilih sudah dihapus -> kembali ke "Semua Outlet".
    if (AdminScope.value.isNotEmpty && !v.contains(AdminScope.value)) {
      AdminScope.pick('');
    } else if (AdminScope.groupId != 0 &&
        !Scope.members.containsKey(AdminScope.groupId)) {
      AdminScope.pick('');
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: AdminScope.outlet,
        builder: (c, sel, _) => Material(
          color: Theme.of(c).colorScheme.surfaceContainerLow,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              // Dropdown outlet, gaya sama seperti pilihan di Laporan Pegawai.
              child: DropdownButtonFormField<String>(
                key: ValueKey(
                    '$sel|${AdminScope.groupId}|${outlets.length}|${Scope.groups.length}'),
                initialValue: AdminScope.groupId != 0 &&
                        Scope.members.containsKey(AdminScope.groupId)
                    ? 'g:${AdminScope.groupId}'
                    : (outlets.contains(sel) ? sel : ''),
                isExpanded: true,
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(16),
                decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: Theme.of(c).colorScheme.outlineVariant)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: Theme.of(c).colorScheme.outlineVariant)),
                    prefixIcon: Icon(Icons.storefront_rounded,
                        color: Theme.of(c).colorScheme.primary)),
                items: [
                  DropdownMenuItem(
                      value: '',
                      child: Text(
                          Scope.restricted
                              ? 'Semua Outlet Saya'
                              : 'Semua Outlet',
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                  // kelompok (Outlet Pusat / Mitra): menyaring semua toko di dalamnya
                  for (final g in Scope.groups)
                    DropdownMenuItem(
                        value: 'g:${g['id']}',
                        child: Row(children: [
                          Icon(
                              g['kind'] == 'pusat'
                                  ? Icons.home_work_outlined
                                  : Icons.groups_outlined,
                              size: 18,
                              color: Theme.of(c).colorScheme.primary),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Text(
                                  '${g['name']} (${Scope.members[g['id']]?.length ?? 0} toko)',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                        ])),
                  for (final o in outlets)
                    DropdownMenuItem(
                        value: o,
                        child: Text(o,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600))),
                ],
                onChanged: (v) {
                  if (v != null && v.startsWith('g:')) {
                    AdminScope.pickGroup(int.parse(v.substring(2)));
                  } else {
                    AdminScope.pick(v ?? '');
                  }
                },
              ),
            ),
            const Divider(height: 1),
          ]),
        ),
      );
}
