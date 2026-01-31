$env:Path += ";C:\flutter\bin"
Write-Host "✅ Added Flutter to PATH for this session."

Write-Host "Checking Flutter..."
flutter doctor

Write-Host "Starting Server App..."
cd server_app
flutter run
