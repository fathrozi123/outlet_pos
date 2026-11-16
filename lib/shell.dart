import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'admin.dart';
import 'closing.dart';
import 'db.dart';
import 'held.dart';
import 'login.dart';
import 'pages.dart';
import 'pos.dart';
import 'rekapitulasi.dart';
import 'report_pegawai.dart';
import 'scope.dart';
import 'stok.dart';

class _Entry {
  final String id, label;
  final IconData icon;
  final List<_Entry> kids;
  const _Entry(this.id, this.label, this.icon, [this.kids = const []]);
}

const _karyawanMenu = [
  _Entry('transaksi', 'Transaksi', Icons.point_of_sale_rounded),
  _Entry('riwayat', 'Riwayat Transaksi', Icons.receipt_long_rounded),
  _Entry('closing', 'Modal & Sinkronisasi', Icons.sync_alt_rounded),
  _Entry('stok', 'Stok Kemasan', Icons.inventory_2_outlined),
  _Entry('pengaturan', 'Pengaturan', Icons.settings_outlined),
];

const _developMenu = [
  _Entry('dashboard', 'Dashboard', Icons.dashboard_rounded),
  _Entry('laporan', 'Laporan', Icons.assessment_outlined, [
    _Entry('ringkasan', 'Ringkasan Penjualan', Icons.bar_chart_rounded),
    _Entry('tren', 'Tren Produk', Icons.trending_up_rounded),
    _Entry('pegawai', 'Laporan Pegawai', Icons.badge_outlined),
    _Entry('absensi', 'Laporan Absensi', Icons.fact_check_outlined),
  ]),
  _Entry('rekapitulasi', 'Rekapitulasi', Icons.calculate_outlined, [
    _Entry('beban', 'Beban', Icons.receipt_outlined),
    _Entry('modal', 'Modal', Icons.account_balance_wallet_outlined),
  ]),
  _Entry('riwayat', 'Riwayat Transaksi', Icons.receipt_long_rounded),
  _Entry('katalog', 'Katalog Produk', Icons.inventory_2_outlined),
  _Entry('inventaris', 'Inventaris', Icons.warehouse_outlined),
  _Entry('outlet', 'Outlet', Icons.storefront_rounded),
  _Entry('staf', 'Akun & Pegawai', Icons.group_outlined),
  _Entry('target', 'Target & Stok Kemasan', Icons.flag_outlined),
  _Entry('pengaturan', 'Pengaturan', Icons.settings_outlined),
];

/// Menu admin (Admin / SPV / Mitra): sama dengan Develop, tanpa Outlet dan
/// Akun & Pegawai.
final _adminMenu = [
  for (final e in _developMenu)
    if (e.id != 'outlet' && e.id != 'staf') e
];

List<_Entry> get _menuNow => Session.isDevelop
    ? _developMenu
    : (Session.isAdmin ? _adminMenu : _karyawanMenu);

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  bool? openPref; // pilihan pengguna untuk sidebar (layar lebar)
  bool open = true; // lebar sidebar dibuka/ditutup (layar lebar)
  bool wide = true; // layar lebar -> sidebar tetap; sempit -> drawer
  bool lbl = true; // tampilkan label menu (ikut lebar sidebar saat animasi)
  late String cur = Session.isAdmin ? 'dashboard' : 'transaksi';
  Timer? _lockT;
  int _ver =
      0; // dinaikkan saat daftar outlet mitra berubah -> halaman dimuat ulang

  @override
  void initState() {
    super.initState();
    // Cek langganan tiap 30 detik: akun yang langganannya habis langsung
    // dikeluarkan dan terkunci.
    _lockT = Timer.periodic(const Duration(seconds: 30), (_) => _checkLock());
  }

  @override
  void dispose() {
    _lockT?.cancel();
    super.dispose();
  }

  Future<void> _checkLock() async {
    if (Session.user == null) return;
    final r = await Db.q('SELECT * FROM users WHERE id=?', [Session.id]);
    if (!mounted || Session.user == null) return;
    if (r.isEmpty) {
      Session.notice = 'Akun tidak ditemukan.';
      _logout();
      return;
    }
    Session.user = r.first;
    Session.tick.value++; // segarkan pemberitahuan langganan di Dashboard
    final lock = await Db.lockReason(r.first);
    if (lock != null) {
      Session.notice = lock;
      _logout();
      return;
    }
    // outlet milik mitra bisa diubah Develop kapan saja
    final before = Scope.mine?.join('|');
    await Scope.load();
    if (mounted && before != Scope.mine?.join('|')) {
      AdminScope.reloadOutlets();
      setState(() => _ver++);
    }
  }

  void _logout() {
    Session.user = null;
    Scope.mine = null;
    AdminScope
        .reset(); // pilihan outlet admin tidak terbawa ke login berikutnya
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  void _go(String id) {
    setState(() => cur = id);
    if (!wide) Navigator.pop(context); // tutup drawer
  }

  String _titleOf(String id) {
    if (id == 'akun') return 'Akun';
    for (final e in _menuNow) {
      if (e.id == id) return e.label;
      for (final k in e.kids) {
        if (k.id == id) return k.label;
      }
    }
    return '';
  }

  /// Bilah pilihan outlet tampil di semua halaman admin, kecuali
  /// Pengaturan dan Akun (yang tidak terkait data outlet).
  bool get _showScope =>
      Session.isAdmin && cur != 'pengaturan' && cur != 'akun';

  /// Isi halaman. Kuncinya memuat outlet terpilih, jadi begitu admin memilih
  /// outlet lain, halaman yang sedang terbuka dibangun ulang dengan data outlet itu.
  Widget _content() => Column(children: [
        if (_showScope) const ScopeBar(),
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: AdminScope.outlet,
            builder: (_, o, __) => KeyedSubtree(
              key: ValueKey(
                  '$cur|${Session.isAdmin ? o : ''}|${Session.isAdmin ? AdminScope.groupId : 0}|$_ver'),
              child: _page(),
            ),
          ),
        ),
      ]);

  Widget _page() {
    switch (cur) {
      case 'transaksi':
        return const PosPage();
      case 'riwayat':
        return const HistoryPage();
      case 'closing':
        return const ClosingPage();
      case 'stok':
        return const StokKemasanPage();
      case 'pengaturan':
        return SettingsPage(onLogout: _logout);
      case 'akun':
        return AccountPage(onLogout: _logout);
      case 'dashboard':
        return const AdminDashboard();
      case 'ringkasan':
        return const ReportSummary();
      case 'tren':
        return const ReportTrend();
      case 'pegawai':
        return const ReportPegawai();
      case 'absensi':
        return const ReportAttendance();
      case 'beban':
        return const BebanPage();
      case 'modal':
        return const ModalPage();
      case 'katalog':
        return const CatalogPage();
      case 'inventaris':
        return const InventoryPage();
      case 'staf':
        return Session.isDevelop ? const StaffPage() : const SizedBox();
      case 'target':
        return const TargetPage();
      case 'outlet':
        return Session.isDevelop ? const OutletPage() : const SizedBox();
    }
    return const SizedBox();
  }

  Widget _avatarWidget(ColorScheme cs, {required double radius}) {
    final pp = Session.user?['photo_path'] as String?;
    final has = pp != null && pp.isNotEmpty && File(pp).existsSync();
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.white,
        foregroundColor: cs.primary,
        backgroundImage: has ? FileImage(File(pp)) : null,
        child: has
            ? null
            : Text(
                Session.name.isEmpty ? '?' : Session.name[0].toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.85,
                ),
              ),
      ),
    );
  }

  Widget _nav(String id, String label, IconData icon,
      {double indent = 0, VoidCallback? onTap}) {
    final sel = cur == id;
    final cs = Theme.of(context).colorScheme;
    if (!lbl) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Tooltip(
          message: label,
          preferBelow: false,
          child: Material(
            color: sel ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap ?? () => _go(id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Icon(
                    icon,
                    size: 22,
                    color: sel ? cs.primary : const Color(0xFF6B5555),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(10 + indent, 3, 10, 3),
      child: Material(
        color: sel ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap ?? () => _go(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(
                icon,
                size: 22,
                color: sel ? cs.primary : const Color(0xFF6B5555),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: sel ? cs.primary : const Color(0xFF2B1B1B),
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              if (sel)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _tile(_Entry e) {
    if (e.kids.isEmpty) return [_nav(e.id, e.label, e.icon)];
    if (!lbl) {
      return [
        _nav(e.id, e.label, e.icon,
            onTap: () => setState(() => openPref = true))
      ];
    }
    final cs = Theme.of(context).colorScheme;
    final hasActiveChild = e.kids.any((k) => k.id == cur);
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Icon(
              e.icon,
              size: 22,
              color: hasActiveChild ? cs.primary : const Color(0xFF6B5555),
            ),
            title: Text(
              e.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: hasActiveChild ? FontWeight.w700 : FontWeight.w500,
                color: hasActiveChild ? cs.primary : const Color(0xFF2B1B1B),
              ),
            ),
            initiallyExpanded: hasActiveChild,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            children: [
              for (final k in e.kids) _nav(k.id, k.label, k.icon, indent: 12)
            ],
          ),
        ),
      )
    ];
  }

  Widget _sidebarBody() {
    final menu = _menuNow;
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      lbl = box.maxWidth > 150;
      return ClipRect(
        child: Column(children: [
          // Kepala sidebar merah: tombol buka-tutup + akun
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary, cs.secondary],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (wide)
                  Align(
                    alignment: lbl ? Alignment.centerRight : Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: lbl ? 8 : 0, top: 4, bottom: 2),
                      child: IconButton(
                        tooltip: open ? 'Tutup Sidebar' : 'Buka Sidebar',
                        color: Colors.white,
                        icon: Icon(open
                            ? Icons.menu_open_rounded
                            : Icons.menu_rounded),
                        onPressed: () => setState(() => openPref = !open),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 8),
                InkWell(
                  onTap: () => _go('akun'),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: lbl ? 14 : 6, vertical: lbl ? 12 : 8),
                    child: lbl
                        ? Row(children: [
                            _avatarWidget(cs, radius: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    Session.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      Session.isAdmin
                                          ? Session.roleLabel
                                          : 'Karyawan • ${Session.outlet}',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                size: 18, color: Colors.white70),
                          ])
                        : Tooltip(
                            message:
                                '${Session.name} (${Session.isAdmin ? Session.roleLabel : Session.outlet})',
                            child: Center(
                              child: _avatarWidget(cs, radius: 17),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [for (final e in menu) ..._tile(e)],
            ),
          ),
          const Divider(height: 1),
          _nav('keluar', 'Keluar', Icons.logout_rounded, onTap: _logout),
          const SizedBox(height: 8),
        ]),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    wide = w >= 700;
    open = openPref ?? (w >= 1000);
    final bg = Theme.of(context).colorScheme.surfaceContainerLow;
    final content = _content();

    if (!wide) {
      // HP / layar sempit: menu jadi drawer (geser dari kiri / tombol menu)
      lbl = true;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _titleOf(cur),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          actions: [
            // Transaksi: simpan pesanan, di sebelah nama outlet
            if (cur == 'transaksi') const HeldButton(color: Colors.white),
            if (!Session.isAdmin && Session.outlet.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.storefront_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          Session.outlet,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        drawer: Drawer(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
          ),
          child: SafeArea(child: _sidebarBody()),
        ),
        body: SafeArea(child: content),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Row(children: [
          // Material (bukan Container berwarna) agar efek sentuh ListTile terlihat
          Material(
            color: bg,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: open ? 260 : 72,
                child: _sidebarBody()),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ]),
      ),
    );
  }
}
