enum AppCategory {
  social,
  entertainment,
  gaming,
  tools,
  allowlisted,
  uncategorized,
}

class UsageCategoryPolicy {
  const UsageCategoryPolicy({
    this.overrides = const <String, AppCategory>{},
    this.allowlistedPackages = const <String>{},
  });

  final Map<String, AppCategory> overrides;
  final Set<String> allowlistedPackages;

  AppCategory categoryFor(String packageName) {
    final normalized = packageName.trim().toLowerCase();
    final override = overrides[packageName] ?? overrides[normalized];
    if (override != null) return override;
    if (allowlistedPackages.contains(normalized)) {
      return AppCategory.allowlisted;
    }

    if (_matches(normalized, const <String>[
      'com.tencent.mm',
      'com.tencent.mobileqq',
      'com.xingin.xhs',
      'com.zhihu.android',
      'com.sina.weibo',
    ])) {
      return AppCategory.social;
    }
    if (_matches(normalized, const <String>[
      'tv.danmaku.bili',
      'com.ss.android.ugc.aweme',
      'com.kuaishou.nebula',
      'com.smile.gifmaker',
    ])) {
      return AppCategory.entertainment;
    }
    if (normalized.contains('.game') ||
        normalized.startsWith('com.tencent.tmgp') ||
        normalized.startsWith('com.miHoYo'.toLowerCase())) {
      return AppCategory.gaming;
    }
    if (normalized.startsWith('com.android.') ||
        normalized.startsWith('com.google.android.') ||
        normalized.startsWith('com.miui.')) {
      return AppCategory.tools;
    }
    return AppCategory.uncategorized;
  }

  bool _matches(String packageName, List<String> packages) {
    return packages.contains(packageName);
  }
}
