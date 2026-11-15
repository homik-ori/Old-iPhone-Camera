# Old iphone Cam

[![Build](https://github.com/homik-ori/Old-iPhone-Camera/actions/workflows/build.yml/badge.svg)](https://github.com/homik-ori/Old-iPhone-Camera/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/homik-ori/Old-iPhone-Camera)](https://github.com/homik-ori/Old-iPhone-Camera/releases/latest)

Нативное iOS-приложение для съёмки с видом камеры старого iPhone. Мягкая картинка без современной цифровой резкости, тёплый оттенок, естественное зерно и ручная выдержка для живого смазывания движения.

Приложение написано на Swift и UIKit. Используются только AVFoundation, Core Image и Photos — без CocoaPods и SPM.

<p align="center">
  <img src="Screenshots/shutter.png" width="310" alt="Ручная выдержка">
  <img src="Screenshots/camera.png" width="310" alt="Главный экран">
</p>
<p align="center"><sub>Скриншоты из iOS Simulator: в нём нет камеры, поэтому видоискатель чёрный.</sub></p>

## Возможности

- Съёмка через основной широкоугольный объектив `builtInWideAngleCamera`.
- `photoQualityPrioritization = .speed` — минимум вычислительной обработки при захвате.
- Приведение кадра к 8 Мп: 3264 × 2448 для 4:3, 3264 × 1836 для 16:9 и 2448 × 2448 для 1:1.
- Мягкая цветокоррекция Core Image: небольшое размытие, вытягивание теней, тёплый баланс белого и слабое зерно.
- Автосохранение JPEG с качеством 0.85 в «Фото».
- Вспышка: авто / вкл / выкл.
- Форматы кадра 4:3, 16:9 и 1:1.
- Коррекция экспозиции от −2.0 до +2.0 с шагом 0.3.
- Таймер 3 и 10 секунд с обратным отсчётом.
- Сетка правила третей.
- Тап-фокус и свайп по экрану для изменения яркости.
- Фиксация фокуса и экспозиции долгим нажатием.
- Зум 1.0x–5.0x, пинч и полукруглое колесо точной настройки.
- Ручная выдержка: 1/125, 1/60, 1/30, 1/15, 1/8, 1/4, 1/2 и 1 секунда.
- Автоподбор ISO под выбранную выдержку и программная компенсация пересвета.
- Просмотр последнего снимка, зум и «Поделиться».

## Ручная выдержка

В панели настроек откройте «ВЫДЕРЖКА». Крайнее левое положение — `АВТО`; камера работает в `continuousAutoExposure`. При выборе фиксированного значения приложение переводит устройство в `setExposureModeCustom(duration:iso:)` и подбирает ISO так, чтобы сохранить текущую яркость сцены.

Если даже минимальное ISO не компенсирует длинную выдержку, при обработке кадра применяется отрицательная `CIExposureAdjust`-компенсация и более мягкое восстановление светов. Тап по видоискателю меняет только точку фокуса и не сбрасывает выбранную выдержку.

## Как получается «вайб» старого iPhone

1. Кадр снимается широкоугольной камерой с приоритетом скорости, чтобы система не успела применить тяжёлую вычислительную обработку.
2. Изображение уменьшается до 8 мегапикселей — это убирает микрорезкость современных сенсоров.
3. Core Image слегка смягчает картинку, приглушает света, поднимает тени и добавляет тёплый оттенок.
4. Поверх накладывается монохромное зерно с прозрачностью около 5%.
5. Результат сохраняется в медиатеку отдельным JPEG.

Параметры подобраны вручную и остаются в коде: `ImageProcessor.swift`.

## Сборка

Нужен macOS с Xcode 15 или новее.

```bash
xcodebuild archive \
  -project iPhone6Camera.xcodeproj \
  -scheme iPhone6Camera \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/iPhone6Camera.xcarchive \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  SKIP_INSTALL=NO
```

Упаковка в IPA:

```bash
mkdir -p build/Payload
cp -R build/iPhone6Camera.xcarchive/Products/Applications/iPhone6Camera.app build/Payload/
cd build && zip -r -y Old_iphone_Cam.ipa Payload
```

Готовый файл собирается в GitHub Actions на `macos-latest` и лежит в артефактах каждой сборки.

## Установка

1. Скачайте `Old_iphone_Cam.ipa` из [последнего релиза](https://github.com/homik-ori/Old-iPhone-Camera/releases/latest).
2. Откройте AltStore → **My Apps → +**.
3. Выберите IPA и подпишите его своим Apple ID.

Файл в релизе не подписан. Для бесплатного Apple ID подпись нужно обновлять раз в 7 дней.

## Структура

```
iPhone6Camera/
├── iPhone6Camera.xcodeproj
├── iPhone6Camera/
│   ├── CameraEngine.swift          # AVCaptureSession, фокус, экспозиция, выдержка, зум
│   ├── ImageProcessor.swift        # ресайз, фильтры, компенсация, сохранение в Photos
│   ├── CameraViewController.swift  # экран камеры и управление
│   ├── PhotoPreviewViewController.swift
│   ├── Models.swift
│   └── Views/                      # затвор, сетка, фокус, зум-диал, панель
└── .github/workflows/build.yml
```

## Лицензия

MIT. Подробности в [LICENSE](LICENSE).
