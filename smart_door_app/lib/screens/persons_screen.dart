// persons_screen.dart — Manage authorized faces (Admin only for delete; enrollment via Enroll Face tab)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/person_model.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class PersonsScreen extends ConsumerStatefulWidget {
  const PersonsScreen({super.key});

  @override
  ConsumerState<PersonsScreen> createState() => _PersonsScreenState();
}

class _PersonsScreenState extends ConsumerState<PersonsScreen> {
  List<PersonModel> _persons = [];
  bool _loading = true;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _persons = await _api.getPersons();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deletePerson(PersonModel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Remove ${p.name}?', style: const TextStyle(color: AppColors.textPrimary)),
        content: Text('${p.name} will no longer have access.', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _api.deletePerson(p.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).user?.isAdmin ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Authorized Persons'),
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.primary)))
          : _persons.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.group_off_rounded, size: 64, color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      const Text('No authorized persons', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                      if (isAdmin) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Use the Enroll Face tab on the home screen to register a person',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _persons.length,
                  itemBuilder: (_, i) {
                    final p = _persons[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            child: p.photoUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: p.photoUrl!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    placeholder: (_, __) => Container(
                                      color: AppColors.surface,
                                      child: const Icon(Icons.person, size: 60, color: AppColors.textMuted),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: AppColors.surface,
                                      child: const Icon(Icons.person, size: 60, color: AppColors.textMuted),
                                    ),
                                  )
                                : Container(
                                    color: AppColors.surface,
                                    child: const Icon(Icons.person, size: 60, color: AppColors.textMuted),
                                  ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                p.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isAdmin)
                              GestureDetector(
                                onTap: () => _deletePerson(p),
                                child: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger, size: 20),
                              ),
                          ]),
                        ),
                      ]),
                    );
                  },
                ),
    );
  }
}
