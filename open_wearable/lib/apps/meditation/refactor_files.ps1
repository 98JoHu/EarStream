# EarStreAM Meditation App - Refactoring Script
# This script reorganizes the meditation app folder structure

$baseDir = "c:\Users\jonas\Documents\Studium - PhD Informatik\EarStream\EarStream\open_wearable\lib\apps\meditation"
$rootDir = "c:\Users\jonas\Documents\Studium - PhD Informatik\EarStream\EarStream\open_wearable"

Write-Host "Starting EarStreAM Meditation App Refactoring..." -ForegroundColor Cyan
Write-Host "Base directory: $baseDir" -ForegroundColor Gray

# Step 1: Create new folder structure
Write-Host "`n[1/9] Creating new folder structure..." -ForegroundColor Yellow

$newFolders = @(
    "$baseDir\config",
    "$baseDir\core",
    "$baseDir\core\biosignals",
    "$baseDir\core\biosignals\sensors",
    "$baseDir\core\meditation",
    "$baseDir\core\storage",
    "$baseDir\models",
    "$baseDir\ui",
    "$baseDir\ui\screens",
    "$baseDir\ui\screens\settings",
    "$baseDir\ui\components",
    "$baseDir\ui\components\biosignal_display",
    "$baseDir\ui\components\meditation_session",
    "$baseDir\ui\components\debug",
    "$baseDir\ui\shared",
    "$baseDir\assets\audio",
    "$baseDir\assets\audio\backgrounds",
    "$baseDir\assets\images"
)

foreach ($folder in $newFolders) {
    if (!(Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "  Created: $folder" -ForegroundColor Green
    }
}

# Step 2: Move .env file
Write-Host "`n[2/9] Moving .env file..." -ForegroundColor Yellow
if (Test-Path "$rootDir\.env") {
    Copy-Item "$rootDir\.env" "$baseDir\config\.env" -Force
    Write-Host "  Moved .env to config/" -ForegroundColor Green
} else {
    Write-Host "  .env not found at root, skipping..." -ForegroundColor Gray
}

# Step 3: Move config files
Write-Host "`n[3/9] Moving configuration files..." -ForegroundColor Yellow
Move-Item "$baseDir\model\meditation_config.dart" "$baseDir\config\" -Force
Move-Item "$baseDir\model\meditation_runtime_config.dart" "$baseDir\config\" -Force
Write-Host "  Moved configuration files" -ForegroundColor Green

# Step 4: Move biosignal files
Write-Host "`n[4/9] Moving biosignal processing files..." -ForegroundColor Yellow
Move-Item "$baseDir\model\activity_detector.dart" "$baseDir\core\biosignals\" -Force
Move-Item "$baseDir\model\band_pass_filter_meditation.dart" "$baseDir\core\biosignals\" -Force
Move-Item "$baseDir\model\ppg_filter_meditation.dart" "$baseDir\core\biosignals\" -Force
Move-Item "$baseDir\model\hrv_calculator.dart" "$baseDir\core\biosignals\" -Force
Move-Item "$baseDir\model\hr_sensor_interface.dart" "$baseDir\core\biosignals\sensors\" -Force
Move-Item "$baseDir\model\earable_hr_sensor.dart" "$baseDir\core\biosignals\sensors\" -Force
Move-Item "$baseDir\model\mock_hr_sensor.dart" "$baseDir\core\biosignals\sensors\" -Force
Write-Host "  Moved biosignal files" -ForegroundColor Green

# Step 5: Move meditation logic files
Write-Host "`n[5/9] Moving meditation logic files..." -ForegroundColor Yellow
Move-Item "$baseDir\model\improved_meditation_controller.dart" "$baseDir\core\meditation\" -Force
Move-Item "$baseDir\model\improved_meditation_llm_service.dart" "$baseDir\core\meditation\" -Force
Move-Item "$baseDir\model\meditation_voice_service.dart" "$baseDir\core\meditation\" -Force
Move-Item "$baseDir\model\personalized_stress_detector.dart" "$baseDir\core\meditation\" -Force
Move-Item "$baseDir\model\outlook_meeting_blocker.dart" "$baseDir\core\meditation\" -Force
Write-Host "  Moved meditation logic files" -ForegroundColor Green

# Step 6: Move storage files
Write-Host "`n[6/9] Moving storage files..." -ForegroundColor Yellow
Move-Item "$baseDir\model\meditation_cache.dart" "$baseDir\core\storage\" -Force
Move-Item "$baseDir\model\meditation_history.dart" "$baseDir\core\storage\" -Force
Move-Item "$baseDir\model\mood_entry.dart" "$baseDir\core\storage\" -Force
Write-Host "  Moved storage files" -ForegroundColor Green

# Step 7: Move user model
Write-Host "`n[7/9] Moving user model..." -ForegroundColor Yellow
Move-Item "$baseDir\model\user_account.dart" "$baseDir\models\" -Force
Write-Host "  Moved user_account.dart" -ForegroundColor Green

# Step 8: Reorganize UI files
Write-Host "`n[8/9] Reorganizing UI files..." -ForegroundColor Yellow

# Rename meditation_view.dart to meditation_screen.dart
Move-Item "$baseDir\view\meditation_view.dart" "$baseDir\ui\screens\meditation_screen.dart" -Force

# Move other screens
Move-Item "$baseDir\widgets\weekly_analysis_screen.dart" "$baseDir\ui\screens\" -Force
Move-Item "$baseDir\view\earstream_settings_pages.dart" "$baseDir\ui\screens\settings\" -Force
Move-Item "$baseDir\widgets\user_onboarding_screen.dart" "$baseDir\ui\screens\settings\" -Force

# Move components
Move-Item "$baseDir\widgets\hr_hrv_display_new.dart" "$baseDir\ui\components\biosignal_display\" -Force
Move-Item "$baseDir\widgets\llm_meditation_widget.dart" "$baseDir\ui\components\meditation_session\" -Force
Move-Item "$baseDir\widgets\breathing_animation.dart" "$baseDir\ui\components\meditation_session\" -Force
Move-Item "$baseDir\widgets\cute_timer_widget.dart" "$baseDir\ui\components\meditation_session\" -Force
Move-Item "$baseDir\widgets\api_debug_widget.dart" "$baseDir\ui\components\debug\" -Force

# Move shared styling
Move-Item "$baseDir\earstream_style.dart" "$baseDir\ui\shared\" -Force

Write-Host "  Reorganized UI files" -ForegroundColor Green

# Step 9: Reorganize assets
Write-Host "`n[9/9] Reorganizing assets..." -ForegroundColor Yellow
Move-Item "$baseDir\assets\Forest.wav" "$baseDir\assets\audio\backgrounds\" -Force
Move-Item "$baseDir\assets\Garden.mp3" "$baseDir\assets\audio\backgrounds\" -Force
Move-Item "$baseDir\assets\Mountain.wav" "$baseDir\assets\audio\backgrounds\" -Force
Move-Item "$baseDir\assets\Ocean_Beach.wav" "$baseDir\assets\audio\backgrounds\" -Force
Move-Item "$baseDir\assets\Peaceful_Nature.wav" "$baseDir\assets\audio\backgrounds\" -Force
Move-Item "$baseDir\assets\meditation_sound.mp3" "$baseDir\assets\audio\" -Force
Move-Item "$baseDir\assets\image.png" "$baseDir\assets\images\" -Force
Write-Host "  Reorganized assets" -ForegroundColor Green

# Step 10: Delete unused files
Write-Host "`n[10/10] Deleting unused files..." -ForegroundColor Yellow
$unusedFiles = @(
    "$baseDir\model\stress_detector.dart",
    "$baseDir\model\user_meditation_profile.dart",
    "$baseDir\view\success_dialog.dart",
    "$baseDir\view\snooze_dialog.dart",
    "$baseDir\view\stress_prompt_dialog.dart",
    "$baseDir\widgets\hr_hrv_chart.dart",
    "$baseDir\widgets\profile_settings_dialog.dart"
)

foreach ($file in $unusedFiles) {
    if (Test-Path $file) {
        Remove-Item $file -Force
        Write-Host "  Deleted: $file" -ForegroundColor Red
    }
}

# Remove now-empty directories
Remove-Item "$baseDir\model" -Force -ErrorAction SilentlyContinue
Remove-Item "$baseDir\view" -Force -ErrorAction SilentlyContinue
Remove-Item "$baseDir\widgets" -Force -ErrorAction SilentlyContinue

Write-Host "`n✓ File reorganization complete!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Run the import update script" -ForegroundColor White
Write-Host "2. Test compilation with 'flutter run'" -ForegroundColor White
