import 'models.dart';

/// App-wide defaults and UI preferences. The actual `AppData` object is owned
/// by `HistoryStore`; this class mutates it and asks `AppState` to persist and
/// notify.
class SettingsStore {
  SettingsStore({
    required this.dataProvider,
    required this.onChanged,
    required this.onSave,
  });

  final AppData Function() dataProvider;
  final void Function() onChanged;
  final void Function() onSave;

  AppData get data => dataProvider();

  void updateDefaults({
    double? temperature,
    double? topP,
    int? topK,
    double? repeatPenalty,
    int? maxTokens,
    String? systemPrompt,
    ResponseFormat? responseFormat,
  }) {
    if (temperature != null) data.defaultTemperature = temperature;
    if (topP != null) data.defaultTopP = topP;
    if (topK != null) data.defaultTopK = topK.clamp(0, 1000);
    if (repeatPenalty != null) {
      data.defaultRepeatPenalty = repeatPenalty.clamp(0.5, 2.0).toDouble();
    }
    if (maxTokens != null) data.defaultMaxTokens = maxTokens;
    if (systemPrompt != null) data.defaultSystemPrompt = systemPrompt;
    if (responseFormat != null) data.defaultResponseFormat = responseFormat;
    _saveAndNotify();
  }

  void updateDefaultLaunch(LaunchSettings launch) {
    data.defaultLaunch = launch;
    _saveAndNotify();
  }

  void setBackgroundGeneration(bool value) {
    data.backgroundGeneration = value;
    _saveAndNotify();
  }

  void setThemeMode(AppThemeMode mode) {
    data.themeMode = mode;
    _saveAndNotify();
  }

  void setFontFamily(AppFontFamily family) {
    data.fontFamily = family;
    _saveAndNotify();
  }

  void setFontScale(double scale) {
    data.fontScale = scale.clamp(0.85, 1.3);
    _saveAndNotify();
  }

  void setUiDensity(UiDensity density) {
    data.uiDensity = density;
    _saveAndNotify();
  }

  void setSidebarWidth(double width) {
    data.sidebarWidth = width.clamp(240.0, 480.0).toDouble();
    _saveAndNotify();
  }

  void setSidebarCollapsed(bool collapsed) {
    data.sidebarCollapsed = collapsed;
    _saveAndNotify();
  }

  void completeSetup() {
    data.setupDone = true;
    _saveAndNotify();
  }

  void _saveAndNotify() {
    onSave();
    onChanged();
  }
}
