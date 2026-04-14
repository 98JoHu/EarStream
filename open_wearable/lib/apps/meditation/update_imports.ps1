# EarStreAM Meditation App - Import Update Script
# This script updates all import statements after the refactoring

$baseDir = "c:\Users\jonas\Documents\Studium - PhD Informatik\EarStream\EarStream\open_wearable\lib\apps\meditation"

Write-Host "Updating import statements..." -ForegroundColor Cyan

# Define import mapping (old path pattern → new path)
$importMappings = @{
    # Config files
    "import '../model/meditation_config.dart';" = "import '../config/meditation_config.dart';"
    "import '../../model/meditation_config.dart';" = "import '../../config/meditation_config.dart';"
    "import '../../../model/meditation_config.dart';" = "import '../../../config/meditation_config.dart';"
    "import '../model/meditation_runtime_config.dart';" = "import '../config/meditation_runtime_config.dart';"
    
    # Biosignal files
    "import '../model/activity_detector.dart';" = "import '../core/biosignals/activity_detector.dart';"
    "import '../model/band_pass_filter_meditation.dart';" = "import '../core/biosignals/band_pass_filter_meditation.dart';"
    "import '../model/ppg_filter_meditation.dart';" = "import '../core/biosignals/ppg_filter_meditation.dart';"
    "import '../model/hrv_calculator.dart';" = "import '../core/biosignals/hrv_calculator.dart';"
    
    # Sensor files
    "import '../model/hr_sensor_interface.dart';" = "import '../core/biosignals/sensors/hr_sensor_interface.dart';"
    "import '../model/earable_hr_sensor.dart';" = "import '../core/biosignals/sensors/earable_hr_sensor.dart';"
    "import '../model/mock_hr_sensor.dart';" = "import '../core/biosignals/sensors/mock_hr_sensor.dart';"
    "import '../../model/hr_sensor_interface.dart';" = "import '../../core/biosignals/sensors/hr_sensor_interface.dart';"
    "import '../../model/earable_hr_sensor.dart';" = "import '../../core/biosignals/sensors/earable_hr_sensor.dart';"
    "import '../../model/mock_hr_sensor.dart';" = "import '../../core/biosignals/sensors/mock_hr_sensor.dart';"
    
    # Meditation logic files
    "import '../model/improved_meditation_controller.dart';" = "import '../core/meditation/improved_meditation_controller.dart';"
    "import '../model/improved_meditation_llm_service.dart';" = "import '../core/meditation/improved_meditation_llm_service.dart';"
    "import '../model/meditation_voice_service.dart';" = "import '../core/meditation/meditation_voice_service.dart';"
    "import '../model/personalized_stress_detector.dart';" = "import '../core/meditation/personalized_stress_detector.dart';"
    "import '../model/outlook_meeting_blocker.dart';" = "import '../core/meditation/outlook_meeting_blocker.dart';"
    
    # Storage files
    "import '../model/meditation_cache.dart';" = "import '../core/storage/meditation_cache.dart';"
    "import '../model/meditation_history.dart';" = "import '../core/storage/meditation_history.dart';"
    "import '../model/mood_entry.dart';" = "import '../core/storage/mood_entry.dart';"
    "import '../../model/mood_entry.dart';" = "import '../../core/storage/mood_entry.dart';"
    
    # User model
    "import '../model/user_account.dart';" = "import '../models/user_account.dart';"
    "import '../../model/user_account.dart';" = "import '../../models/user_account.dart';"
    "import '../../../model/user_account.dart';" = "import '../../../models/user_account.dart';"
    
    # View/Screen files
    "import '../view/meditation_view.dart';" = "import '../ui/screens/meditation_screen.dart';"
    "import '../view/earstream_settings_pages.dart';" = "import '../ui/screens/settings/earstream_settings_pages.dart';"
    "import '../../view/earstream_settings_pages.dart';" = "import '../../ui/screens/settings/earstream_settings_pages.dart';"
    "import 'earstream_settings_pages.dart';" = "import '../settings/earstream_settings_pages.dart';"
    
    # Widget files
    "import '../widgets/weekly_analysis_screen.dart';" = "import '../ui/screens/weekly_analysis_screen.dart';"
    "import '../../widgets/weekly_analysis_screen.dart';" = "import '../../ui/screens/weekly_analysis_screen.dart';"
    "import '../widgets/user_onboarding_screen.dart';" = "import '../ui/screens/settings/user_onboarding_screen.dart';"
    "import '../../widgets/user_onboarding_screen.dart';" = "import '../../ui/screens/settings/user_onboarding_screen.dart';"
    "import '../widgets/hr_hrv_display_new.dart';" = "import '../ui/components/biosignal_display/hr_hrv_display_new.dart';"
    "import '../../widgets/hr_hrv_display_new.dart';" = "import '../../ui/components/biosignal_display/hr_hrv_display_new.dart';"
    "import '../widgets/llm_meditation_widget.dart';" = "import '../ui/components/meditation_session/llm_meditation_widget.dart';"
    "import '../../widgets/llm_meditation_widget.dart';" = "import '../../ui/components/meditation_session/llm_meditation_widget.dart';"
    "import '../widgets/breathing_animation.dart';" = "import '../ui/components/meditation_session/breathing_animation.dart';"
    "import '../../widgets/breathing_animation.dart';" = "import '../../ui/components/meditation_session/breathing_animation.dart';"
    "import '../widgets/cute_timer_widget.dart';" = "import '../ui/components/meditation_session/cute_timer_widget.dart';"
    "import '../widgets/api_debug_widget.dart';" = "import '../ui/components/debug/api_debug_widget.dart';"
    "import '../../widgets/api_debug_widget.dart';" = "import '../../ui/components/debug/api_debug_widget.dart';"
    "import '../../../widgets/api_debug_widget.dart';" = "import '../../../ui/components/debug/api_debug_widget.dart';"
    
    # Shared styling
    "import 'package:open_wearable/apps/meditation/earstream_style.dart';" = "import 'package:open_wearable/apps/meditation/ui/shared/earstream_style.dart';"
    "import '../earstream_style.dart';" = "import '../ui/shared/earstream_style.dart';"
    "import '../../earstream_style.dart';" = "import '../../ui/shared/earstream_style.dart';"
    "import '../../../earstream_style.dart';" = "import '../../../ui/shared/earstream_style.dart';"
    "import 'earstream_style.dart';" = "import '../shared/earstream_style.dart';"
}

# Get all .dart files recursively
$dartFiles = Get-ChildItem -Path $baseDir -Filter "*.dart" -Recurse

$totalReplacements = 0

foreach ($file in $dartFiles) {
    $content = Get-Content $file.FullName -Raw
    $originalContent = $content
    $fileReplacements = 0
    
    # Apply all mappings
    foreach ($oldImport in $importMappings.Keys) {
        $newImport = $importMappings[$oldImport]
        if ($content -match [regex]::Escape($oldImport)) {
            $content = $content -replace [regex]::Escape($oldImport), $newImport
            $fileReplacements++
        }
    }
    
    # Only write if changes were made
    if ($content -ne $originalContent) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "  Updated $($file.Name): $fileReplacements replacements" -ForegroundColor Green
        $totalReplacements += $fileReplacements
    }
}

Write-Host "`n✓ Import update complete!" -ForegroundColor Green
Write-Host "Total replacements: $totalReplacements" -ForegroundColor Cyan

# Update .env path in meditation_config.dart
Write-Host "`nUpdating .env path in meditation_config.dart..." -ForegroundColor Yellow
$configFile = "$baseDir\config\meditation_config.dart"
if (Test-Path $configFile) {
    $content = Get-Content $configFile -Raw
    # Update the dotenv.load path
    $content = $content -replace "await dotenv\.load\(fileName: '\.env'\);", "await dotenv.load(fileName: 'lib/apps/meditation/config/.env');"
    Set-Content -Path $configFile -Value $content -NoNewline
    Write-Host "  Updated .env path" -ForegroundColor Green
}

# Update asset paths
Write-Host "`nUpdating asset paths..." -ForegroundColor Yellow
$controllerFile = "$baseDir\core\meditation\improved_meditation_controller.dart"
if (Test-Path $controllerFile) {
    $content = Get-Content $controllerFile -Raw
    $content = $content -replace "'Ocean_Beach\.wav'", "'lib/apps/meditation/assets/audio/backgrounds/Ocean_Beach.wav'"
    $content = $content -replace "'Mountain\.wav'", "'lib/apps/meditation/assets/audio/backgrounds/Mountain.wav'"
    $content = $content -replace "'Forest\.wav'", "'lib/apps/meditation/assets/audio/backgrounds/Forest.wav'"
    $content = $content -replace "'Garden\.mp3'", "'lib/apps/meditation/assets/audio/backgrounds/Garden.mp3'"
    $content = $content -replace "'Peaceful_Nature\.wav'", "'lib/apps/meditation/assets/audio/backgrounds/Peaceful_Nature.wav'"
    $content = $content -replace "'meditation_sound\.mp3'", "'lib/apps/meditation/assets/audio/meditation_sound.mp3'"
    Set-Content -Path $controllerFile -Value $content -NoNewline
    Write-Host "  Updated asset paths in controller" -ForegroundColor Green
}

$configFileAssets = "$baseDir\config\meditation_config.dart"
if (Test-Path $configFileAssets) {
    $content = Get-Content $configFileAssets -Raw
    $content = $content -replace "'meditation_sound\.mp3'", "'lib/apps/meditation/assets/audio/meditation_sound.mp3'"
    Set-Content -Path $configFileAssets -Value $content -NoNewline
    Write-Host "  Updated asset paths in config" -ForegroundColor Green
}

Write-Host "`n✓ All paths updated!" -ForegroundColor Green
Write-Host "`nReady to test with 'flutter run'" -ForegroundColor Cyan
