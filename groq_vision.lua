require "import"
import "android.graphics.Bitmap"
import "android.graphics.Canvas"
import "android.graphics.Paint"
import "android.util.Base64"
import "java.io.ByteArrayOutputStream"
import "org.json.JSONObject"
import "org.json.JSONArray"
import "android.app.AlertDialog"
import "android.widget.EditText"
import "android.widget.TextView"
import "android.widget.Button"
import "android.widget.LinearLayout"
import "android.widget.ScrollView"
import "android.content.Context"
import "android.content.ClipData"
import "android.content.ClipboardManager"
import "android.view.WindowManager"
import "android.view.Display"
import "android.view.ViewGroup"
import "android.os.Build"
import "android.accessibilityservice.AccessibilityService$TakeScreenshotCallback"
import "java.net.URL"
import "java.net.HttpURLConnection"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.io.File"
import "java.io.FileOutputStream"
import "java.lang.Thread"
import "java.lang.String"
import "java.lang.Runnable"
import "android.os.Handler"
import "android.os.Looper"
import "java.util.HashMap"
import "com.androlua.Http"

local mainHandler = Handler(Looper.getMainLooper())

-- ====================================================================
-- KONFIGURASI VERSI & GITHUB AUTO-UPDATE
-- ====================================================================
local CURRENT_VERSION = "2.0.9"
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/novanblind/DeskripsilayarGroqAI/main/groq_vision.lua"

local defaultImageInstruction = [[DILARANG KERAS menggunakan kalimat pengantar, pembuka, atau basa-basi apa pun seperti 'Berdasarkan gambar...', 'Berikut adalah...', 'Gambar ini memperlihatkan...', atau sejenisnya. 

LANGSUNG mulai kata pertama dengan menyebutkan objek utama yang terlihat. Deskripsikan gambar atau tampilan layar secara jelas, natural, dan profesional dalam bahasa Indonesia. Susun narasi visual yang mengalir dari elemen paling dominan ke objek, karakter, lingkungan, dan detail sekitarnya. Jelaskan warna, bentuk, ukuran, tekstur, posisi, pencahayaan, suasana, komposisi, serta hubungan antarelemen tanpa berlebihan atau mengarang informasi. Abaikan elemen antarmuka ponsel yang tidak relevan, seperti indikator sinyal, baterai, waktu, notifikasi, atau ikon sistem lainnya, kecuali jika secara khusus diminta untuk menjelaskannya.

Jika terdapat manusia atau karakter, gambarkan penampilan, pakaian, ekspresi, arah pandangan, gestur, dan kesan emosional yang tampak. Jelaskan pula kedalaman ruang, objek di depan, tengah, dan belakang, serta cara komposisi mengarahkan perhatian.

Jika gambar berisi surat, dokumen, formulir, poster, papan, atau teks lainnya, bacakan dan transkripsikan seluruh teks yang terlihat secara akurat. Pertahankan urutan pembacaan sesuai tata letak gambar.

Jangan gunakan pembuka umum seperti 'Gambar ini menunjukkan...', penomoran, bullet point, subjudul, atau kategori. Dasarkan setiap pernyataan pada hal yang benar-benar terlihat; nyatakan ketidakpastian jika diperlukan. Pastikan isi surat atau dokumen disampaikan secara lengkap sebelum memberikan deskripsi visual dan kesan suasana keseluruhan.]]

local defaultVideoInstruction = [[Deskripsikan video secara berurutan secara jelas, natural, dan profesional dalam bahasa Indonesia. Susun narasi visual yang mengalir dari elemen paling dominan ke objek, karakter, lingkungan, dan detail sekitarnya. Jelaskan warna, bentuk, ukuran, tekstur, posisi, pencahayaan, suasana, komposisi, serta hubungan antarelemen tanpa berlebihan atau mengarang informasi. Abaikan elemen antarmuka ponsel yang tidak relevan, seperti indikator sinyal, baterai, waktu, notifikasi, atau ikon sistem lainnya, kecuali jika secara khusus diminta untuk menjelaskannya.

Jika terdapat manusia atau karakter, gambarkan penampilan, pakaian, ekspresi, arah pandangan, gestur, dan kesan emosional yang tampak. Jelaskan pula kedalaman ruang, objek di depan, tengah, dan belakang, serta cara komposisi mengarahkan perhatian.

Jika gambar berisi surat, dokumen, formulir, poster, papan, atau teks lainnya, bacakan dan transkripsikan seluruh teks yang terlihat secara akurat. Pertahankan urutan pembacaan sesuai tata letak gambar. Jika ini adalah urutan gambar (video), jelaskan pergerakan dan perubahan yang terjadi dari awal hingga akhir dengan alur cerita yang masuk akal.

Jangan gunakan pembuka umum seperti 'Gambar ini menunjukkan...', penomoran, bullet point, subjudul, atau kategori. Dasarkan setiap pernyataan pada hal yang benar-benar terlihat; nyatakan ketidakpastian jika diperlukan. Pastikan isi surat atau dokumen disampaikan secara lengkap sebelum memberikan deskripsi visual dan kesan suasana keseluruhan.]]

local defaultTextInstruction = [[Ekstrak dan transkripsikan seluruh teks yang terlihat pada tampilan layar ini secara akurat, lengkap, dan berurutan dari atas ke bawah sesuai tata letak aslinya.

DILARANG memberikan kata pengantar, penjelasan, pembuka (seperti "Teks pada layar adalah:", "Berikut teksnya:"), penutup, ataupun deskripsi visual mengenai elemen layar.

Tampilkan HANYA teks asli yang tertulis di layar persis apa adanya tanpa basa-basi. Jika tidak ada teks sama sekali yang terlihat, tuliskan: Tidak ada teks yang terdeteksi.]]

local sp = service.getSharedPreferences("groq_vision_desc_config", Context.MODE_PRIVATE)

-- ====================================================================
-- MANAJEMEN JALUR BERKAS SCRIPT LOKAL
-- ====================================================================
local function getScriptFilePath()
  local src = debug.getinfo(1, "S").source
  if src and src:sub(1, 1) == "@" then
    return src:sub(2)
  end
  local candidateDirs = {
    "/sdcard/jieshuo/plugin/DeskripsilayarGroqAI/",
    "/storage/emulated/0/jieshuo/plugin/DeskripsilayarGroqAI/",
    "/sdcard/jieshuo/plugin/Deskripsi Layar Groq/",
    "/storage/emulated/0/jieshuo/plugin/Deskripsi Layar Groq/",
    "/sdcard/jieshuo/plugin/DeskripsiLayarGroq/",
    "/storage/emulated/0/jieshuo/plugin/DeskripsiLayarGroq/"
  }
  local candidateNames = {"main.lua", "groq_vision.lua"}
  for _, dir in ipairs(candidateDirs) do
    for _, name in ipairs(candidateNames) do
      local p = dir .. name
      if File(p).exists() then return p end
    end
  end
  return "/sdcard/jieshuo/plugin/DeskripsilayarGroqAI/main.lua"
end

local function getScriptDir()
  local path = getScriptFilePath()
  if path then
    return path:match("(.*/)")
  end
  return "/sdcard/jieshuo/plugin/DeskripsilayarGroqAI/"
end

local function readLocalApiKeyFile()
  local dir = getScriptDir()
  local candidates = {
    dir and (dir .. "api_key.txt"),
    "/sdcard/jieshuo/plugin/Deskripsi Layar Groq/api_key.txt",
    "/sdcard/jieshuo/plugin/DeskripsilayarGroqAI/api_key.txt",
    "/sdcard/jieshuo/plugin/DeskripsiLayarGroq/api_key.txt",
    "/sdcard/jieshuo/groq_api_key.txt"
  }
  for _, filePath in ipairs(candidates) do
    if filePath and File(filePath).exists() then
      local f = io.open(filePath, "r")
      if f then
        local content = f:read("*all")
        f:close()
        if content then
          local key = content:gsub("^%s*(.-)%s*$", "%1")
          if key ~= "" then return key end
        end
      end
    end
  end
  return ""
end

-- ====================================================================
-- SISTEM MANAJEMEN MULTI KUNCI API (UTAMA & CADANGAN) — sama seperti
-- skrip "Deskripsi kamera Groq by Novan": 1 kunci utama + 2 cadangan,
-- dengan rotasi otomatis saat kunci aktif habis kuota/limit.
-- ====================================================================
local currentKeyIndex = 1

local function getAvailableApiKeys()
  local list = {}
  local seen = {}

  -- Kunci Utama (cek kustom dulu, jika kosong baca api_key.txt)
  local k1 = sp.getString("custom_api_key", "")
  local k1Source = "Kustom"
  if k1 == "" then
    k1 = readLocalApiKeyFile()
    k1Source = "api_key.txt"
  end
  if k1 ~= "" then
    table.insert(list, { key = k1, name = "Kunci Utama", source = k1Source })
    seen[k1] = true
  end

  -- Kunci Cadangan 1
  local k2 = sp.getString("backup_api_key_1", "")
  if k2 ~= "" and not seen[k2] then
    table.insert(list, { key = k2, name = "Kunci Cadangan 1", source = "Cadangan 1" })
    seen[k2] = true
  end

  -- Kunci Cadangan 2
  local k3 = sp.getString("backup_api_key_2", "")
  if k3 ~= "" and not seen[k3] then
    table.insert(list, { key = k3, name = "Kunci Cadangan 2", source = "Cadangan 2" })
    seen[k3] = true
  end

  return list
end

local function getActiveKeyStatusLabel()
  local keys = getAvailableApiKeys()
  if #keys == 0 then return "Belum Diatur" end
  local idx = currentKeyIndex
  if idx > #keys then idx = 1 end
  return keys[idx].name .. " Aktif (" .. #keys .. " kunci tersimpan)"
end

-- ====================================================================
-- PENGATURAN LAINNYA
-- ====================================================================
local function getModelName() return sp.getString("model_name", "qwen/qwen3.8-27b") end
local function setModelName(m) sp.edit().putString("model_name", m).apply() end

-- Daftar model vision Groq yang diketahui bekerja dengan input gambar.
-- Ditampilkan di menu "Ganti Model" agar pengguna tidak perlu mengetik
-- manual, tapi opsi "Kustom" tetap disediakan untuk model lain.
-- CATATAN: dari 11 model yang aktif di akun Groq pengguna saat ini
-- (canopylabs/orpheus-arabic-saudi, canopylabs/orpheus-v1-english,
-- openai/gpt-oss-20b, meta-llama/llama-prompt-guard-2-86m,
-- qwen/qwen3.8-27b, whisper-large-v3, whisper-large-v3-turbo,
-- allam-2-7b, openai/gpt-oss-120b, openai/gpt-oss-safeguard-20b,
-- meta-llama/llama-prompt-guard-2-22m), HANYA qwen/qwen3.8-27b yang
-- mendukung input gambar (image_url). Sisanya adalah model teks
-- (gpt-oss, allam), suara/TTS (orpheus, whisper), atau guard/classifier
-- (prompt-guard) — memilihnya di sini akan membuat permintaan gambar
-- gagal dengan error 400. Jika akun mendapat akses model vision lain
-- di kemudian hari, tambahkan ke daftar ini atau pakai opsi "Kustom".
local knownVisionModels = {
  "qwen/qwen3.8-27b"
}

local function getReasoningEffort() return sp.getString("reasoning_effort", "none") end
local function setReasoningEffort(r) sp.edit().putString("reasoning_effort", r).apply() end

local function getScanMode() return sp.getString("scan_feature_mode", "visual_desc") end
local function setScanMode(m) sp.edit().putString("scan_feature_mode", m).apply() end

local function getVideoDuration() return sp.getInt("video_duration", 10) end
local function setVideoDuration(d) sp.edit().putInt("video_duration", d).apply() end

local function getResolutionMode() return sp.getString("scan_resolution", "720") end
local function setResolutionMode(r) sp.edit().putString("scan_resolution", r).apply() end

local function getImageInstruction() return sp.getString("custom_instruction", defaultImageInstruction) end
local function setImageInstruction(i) sp.edit().putString("custom_instruction", i).apply() end

local function getVideoInstruction() return sp.getString("custom_video_instruction", defaultVideoInstruction) end
local function setVideoInstruction(i) sp.edit().putString("custom_video_instruction", i).apply() end

local function getTextInstruction() return sp.getString("custom_text_instruction", defaultTextInstruction) end
local function setTextInstruction(i) sp.edit().putString("custom_text_instruction", i).apply() end

local function displayOverlayDialog(builder)
  local dialog = builder.create()
  local window = dialog.getWindow()
  if window then
    window.setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  end
  dialog.show()
  return dialog
end

local chatHistory = {}
local currentSysInstruction = defaultImageInstruction
local showMainMenu
local showApiKeyDialog
local showModelDialog
local startScreenDescription
local showChatDialog
local checkAppUpdate

-- ====================================================================
-- SISTEM PEMBARUAN & DIALOG AUTO-UPDATE
-- ====================================================================
local function parseVersion(verStr)
  local parts = {}
  for num in string.gmatch(verStr or "", "(%d+)") do
    table.insert(parts, tonumber(num))
  end
  return parts
end

local function isNewerVersion(remoteVer, localVer)
  local r = parseVersion(remoteVer)
  local l = parseVersion(localVer)
  local maxLen = math.max(#r, #l)
  for i = 1, maxLen do
    local rNum = r[i] or 0
    local lNum = l[i] or 0
    if rNum > lNum then return true end
    if rNum < lNum then return false end
  end
  return false
end

local function saveNewScript(newCode, targetPath)
  local success = false
  pcall(function()
    local f = File(targetPath)
    if not f.getParentFile().exists() then
      f.getParentFile().mkdirs()
    end
    local fos = FileOutputStream(f)
    fos.write(String(newCode).getBytes("UTF-8"))
    fos.flush()
    fos.close()
    success = true
  end)
  return success
end

local function showNoUpdateDialog()
  mainHandler.post(Runnable{
    run = function()
      local builder = AlertDialog.Builder(service)
        .setTitle("Tidak Ada Versi Baru")
        .setMessage("Anda sudah menggunakan versi terbaru: " .. CURRENT_VERSION)
        .setPositiveButton("Oke", function(dialog)
          dialog.dismiss()
        end)
      displayOverlayDialog(builder)
      pcall(function() service.speak("Tidak ada versi baru. Versi saat ini: " .. CURRENT_VERSION) end)
    end
  })
end

local function showDownloadCompleteDialog(newVersion)
  mainHandler.post(Runnable{
    run = function()
      local builder = AlertDialog.Builder(service)
        .setTitle("Download Selesai")
        .setMessage("Pembaruan ke versi " .. tostring(newVersion) .. " berhasil diunduh dan dipasang. Silakan buka kembali plugin untuk menerapkan.")
        .setPositiveButton("Oke", function(dialog)
          dialog.dismiss()
        end)
      displayOverlayDialog(builder)
      pcall(function() service.speak("Download selesai.") end)
    end
  })
end

local function showUpdateAvailableDialog(remoteVersion, newScriptCode)
  mainHandler.post(Runnable{
    run = function()
      local message = "Versi baru tersedia: " .. tostring(remoteVersion) .. "\nVersi yang digunakan: " .. tostring(CURRENT_VERSION)
      local builder = AlertDialog.Builder(service)
        .setTitle("Versi Baru Tersedia")
        .setMessage(message)
        .setPositiveButton("Perbarui", function(dialog)
          dialog.dismiss()
          service.speak("Sedang mengunduh pembaruan...")
          Thread(Runnable{
            run = function()
              local localPath = getScriptFilePath()
              if localPath and saveNewScript(newScriptCode, localPath) then
                showDownloadCompleteDialog(remoteVersion)
              else
                mainHandler.post(Runnable{
                  run = function()
                    service.speak("Gagal menyimpan berkas pembaruan.")
                  end
                })
              end
            end
          }).start()
        end)
        .setNegativeButton("Nanti", function(dialog)
          dialog.dismiss()
        end)
      displayOverlayDialog(builder)
      pcall(function() service.speak("Versi baru tersedia. Versi baru: " .. tostring(remoteVersion) .. ". Versi yang Anda gunakan: " .. tostring(CURRENT_VERSION)) end)
    end
  })
end

checkAppUpdate = function(isManual)
  if GITHUB_RAW_URL:find("USERNAME/REPO_NAME") then return end
  local fetchUrl = GITHUB_RAW_URL .. "?t=" .. tostring(os.time())

  if isManual then
    service.speak("Memeriksa versi baru...")
  end

  Thread(Runnable{
    run = function()
      local content = nil
      local resCode = 0

      pcall(function()
        local url = URL(fetchUrl)
        local conn = url.openConnection()
        conn.setRequestMethod("GET")
        conn.setConnectTimeout(10000)
        conn.setReadTimeout(15000)
        conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; Mobile)")
        conn.setRequestProperty("Cache-Control", "no-cache")
        conn.setInstanceFollowRedirects(true)

        resCode = conn.getResponseCode()
        if resCode == 200 then
          local stream = conn.getInputStream()
          local reader = BufferedReader(InputStreamReader(stream, "UTF-8"))
          local lines = {}
          local line = reader.readLine()
          while line ~= nil do
            table.insert(lines, line)
            line = reader.readLine()
          end
          reader.close()
          content = table.concat(lines, "\n")
        end
        conn.disconnect()
      end)

      if resCode == 200 and content and #content >= 200 then
        local remoteVersion = content:match('CURRENT_VERSION%s*=%s*["\']([^"\']+)["\']')
        if remoteVersion and isNewerVersion(remoteVersion, CURRENT_VERSION) then
          showUpdateAvailableDialog(remoteVersion, content)
        else
          if isManual then
            showNoUpdateDialog()
          end
        end
      else
        if isManual then
          mainHandler.post(Runnable{
            run = function()
              local builder = AlertDialog.Builder(service)
                .setTitle("Pemeriksaan Gagal")
                .setMessage("Gagal terhubung ke server pembaruan (Kode respons: " .. tostring(resCode) .. ").")
                .setPositiveButton("Oke", function(dialog)
                  dialog.dismiss()
                end)
              displayOverlayDialog(builder)
              pcall(function() service.speak("Gagal memeriksa versi baru.") end)
            end
          })
        end
      end
    end
  }).start()
end

-- ====================================================================
-- PENGOLAHAN GAMBAR (KOMPRESI & BASE64 DENGAN OPTIMASI RESOLUSI)
-- ====================================================================

-- Menentukan batas sisi terpendek (limit) dan kualitas JPEG berdasarkan
-- resolusi pilihan pengguna. isTextMode menaikkan batas minimum karena
-- mode Pindai Teks butuh ketajaman lebih tinggi agar akurat, terlepas
-- dari resolusi hemat-kuota yang mungkin dipilih untuk mode lain.
local function resolveLimitQuality(resMode, isVideoMode, isTextMode)
  local targetQuality = 75
  local limit = 720

  if resMode == "original" then
    limit = isVideoMode and 720 or 0
    targetQuality = isVideoMode and 75 or 85
  elseif resMode == "1080" then
    limit = isVideoMode and 640 or 1080
    targetQuality = isVideoMode and 70 or 80
  elseif resMode == "720" then
    limit = isVideoMode and 480 or 720
    targetQuality = isVideoMode and 70 or 75
  elseif resMode == "480" then
    limit = isVideoMode and 360 or 480
    targetQuality = isVideoMode and 65 or 70
  end

  if isTextMode then
    if limit ~= 0 then
      limit = math.max(limit, 720)
    end
    targetQuality = math.max(targetQuality, 82)
  end

  return limit, targetQuality
end

local function getVideoFrameLimit()
  local limit, _ = resolveLimitQuality(getResolutionMode(), true, false)
  return limit
end

-- Downscale bitmap secara mandiri ke batas sisi terpendek tertentu.
-- Dipakai untuk mengecilkan tiap frame video SEBELUM digabung, supaya
-- kanvas gabungan tidak pernah berukuran resolusi layar penuh x 3
-- (mencegah risiko OutOfMemoryError di perangkat RAM kecil).
local function downscaleBitmapToLimit(bitmap, limit)
  if not bitmap then return nil end
  local w = bitmap.getWidth()
  local h = bitmap.getHeight()
  local minSide = math.min(w, h)
  if limit <= 0 or minSide <= limit then
    return bitmap
  end
  local scale = limit / minSide
  local newW = math.max(1, math.floor(w * scale))
  local newH = math.max(1, math.floor(h * scale))
  local scaled = nil
  pcall(function()
    scaled = Bitmap.createScaledBitmap(bitmap, newW, newH, true)
  end)
  if scaled then
    pcall(function() bitmap.recycle() end)
    return scaled
  end
  return bitmap
end

local function bitmapToBase64(bitmap, isVideoMode, isTextMode)
  local limit, targetQuality = resolveLimitQuality(getResolutionMode(), isVideoMode, isTextMode)

  local w = bitmap.getWidth()
  local h = bitmap.getHeight()
  local minSide = math.min(w, h)
  local scale = 1.0

  if limit > 0 and minSide > limit then
    scale = limit / minSide
  end

  local targetBitmap = bitmap
  local needRecycle = false

  if bitmap.getConfig() == Bitmap.Config.HARDWARE or scale < 1.0 then
    local copyBmp = bitmap.copy(Bitmap.Config.ARGB_8888, false)
    if scale < 1.0 then
      local newW = math.max(1, math.floor(w * scale))
      local newH = math.max(1, math.floor(h * scale))
      targetBitmap = Bitmap.createScaledBitmap(copyBmp, newW, newH, true)
      pcall(function() copyBmp.recycle() end)
    else
      targetBitmap = copyBmp
    end
    needRecycle = true
  end

  local baos = ByteArrayOutputStream()
  targetBitmap.compress(Bitmap.CompressFormat.JPEG, targetQuality, baos)
  local bytes = baos.toByteArray()
  baos.close()
  local base64Str = Base64.encodeToString(bytes, Base64.NO_WRAP)

  if needRecycle and targetBitmap ~= bitmap then
    pcall(function() targetBitmap.recycle() end)
  end
  pcall(function() bitmap.recycle() end)

  return base64Str
end

-- Membungkus service.takeScreenshot(). PENTING: takeScreenshot() dapat
-- melempar exception SECARA SINKRON (mis. kapabilitas screenshot belum
-- diaktifkan di konfigurasi accessibility service, atau perangkat tidak
-- mendukung). Sebelumnya exception ini ditelan diam-diam oleh pcall dan
-- callback tidak pernah terpanggil, membuat aplikasi macet tanpa pesan
-- apa pun. Sekarang exception ditangkap dan callback(false, ...) selalu
-- dipanggil supaya pengguna mendapat pesan suara yang jelas.
local function captureSingleFrame(callback)
  local ok, errMsg = pcall(function()
    service.takeScreenshot(Display.DEFAULT_DISPLAY, service.getMainExecutor(), TakeScreenshotCallback{
      onSuccess = function(screenshotResult)
        local bmp = nil
        pcall(function()
          local hwBuffer = screenshotResult.getHardwareBuffer()
          local colorSpace = screenshotResult.getColorSpace()
          local rawBmp = Bitmap.wrapHardwareBuffer(hwBuffer, colorSpace)
          if rawBmp then
            bmp = rawBmp.copy(Bitmap.Config.ARGB_8888, false)
            pcall(function() rawBmp.recycle() end)
          end
          if hwBuffer then hwBuffer.close() end
        end)
        if bmp then
          callback(true, bmp)
        else
          callback(false, "Gagal mengekstrak bitmap dari screenshot.")
        end
      end,
      onFailure = function(errorCode)
        callback(false, "Gagal mengambil tangkapan layar. Kode: " .. tostring(errorCode))
      end
    })
  end)

  if not ok then
    callback(false, "Gagal memulai tangkapan layar (" .. tostring(errMsg) .. "). Pastikan izin tangkapan layar aksesibilitas sudah aktif.")
  end
end

-- ====================================================================
-- GROQ API ASINKRON DENGAN DUKUNGAN KUNCI UTAMA & CADANGAN OTOMATIS
-- (mekanisme rotasi kunci sama dengan skrip "Deskripsi kamera Groq")
-- ====================================================================
local REQUEST_TIMEOUT_MS = 15000

local function sendGroqChat(userText, mediaData, onComplete)
  local keyList = getAvailableApiKeys()

  if #keyList == 0 then
    onComplete(false, "Kunci API Groq belum ditemukan. Silakan atur di menu pengaturan.")
    showApiKeyDialog()
    return
  end

  if currentKeyIndex > #keyList then
    currentKeyIndex = 1
  end

  if mediaData then
    table.insert(chatHistory, {
      role = "user",
      content = {
        { type = "text", text = userText },
        { type = "image_url", image_url = { url = "data:image/jpeg;base64," .. mediaData } }
      }
    })
  else
    table.insert(chatHistory, {
      role = "user",
      content = userText
    })
  end

  local activeModel = getModelName()
  local scanMode = getScanMode()

  -- Batas token disesuaikan dengan jenis permintaan: mode video harus
  -- menceritakan 3 kondisi layar sekaligus, dan mode pindai teks bisa
  -- berisi paragraf panjang, jadi keduanya butuh ruang lebih besar
  -- daripada percakapan lanjutan (follow-up) biasa.
  local maxTokens = 1200
  if mediaData then
    if scanMode == "video_desc" then
      maxTokens = 3000
    elseif scanMode == "text_ocr" then
      maxTokens = 2500
    else
      maxTokens = 2000
    end
  end

  local jsonPayload = JSONObject()
  jsonPayload.put("model", activeModel)
  jsonPayload.put("temperature", 0.1)
  jsonPayload.put("max_tokens", maxTokens)

  -- PENTING: model seri Qwen3 (mis. qwen/qwen3.8-27b, qwen/qwen3.6-27b)
  -- berjalan dalam mode "thinking" dengan reasoning_effort maksimum
  -- ("xhigh") SECARA DEFAULT jika parameter ini tidak dikirim. Tanpa
  -- ini, token <think>...</think> bisa menghabiskan seluruh max_tokens
  -- sebelum jawaban asli sempat ditulis, atau malah ikut terbaca oleh
  -- service.speak(). Untuk kasus deskripsi/OCR yang butuh jawaban
  -- langsung, mode instruct (reasoning_effort="none") lebih cocok.
  -- reasoning_format="hidden" adalah jaring pengaman tambahan agar
  -- konten reasoning tidak pernah ikut ke field "content" walau pada
  -- model/parameter lain yang mungkin tetap mengembalikannya.
  local reasoningEffort = getReasoningEffort()
  if reasoningEffort and reasoningEffort ~= "" and reasoningEffort ~= "default" then
    jsonPayload.put("reasoning_effort", reasoningEffort)
  end
  jsonPayload.put("reasoning_format", "hidden")

  local messagesArray = JSONArray()
  if currentSysInstruction and currentSysInstruction ~= "" then
    local sysObj = JSONObject()
    sysObj.put("role", "system")
    sysObj.put("content", currentSysInstruction)
    messagesArray.put(sysObj)
  end

  for _, msg in ipairs(chatHistory) do
    local msgObj = JSONObject()
    msgObj.put("role", msg.role)
    if type(msg.content) == "string" then
      msgObj.put("content", msg.content)
    elseif type(msg.content) == "table" then
      local contentArr = JSONArray()
      for _, item in ipairs(msg.content) do
        local itemObj = JSONObject()
        itemObj.put("type", item.type)
        if item.type == "text" then
          itemObj.put("text", item.text)
        elseif item.type == "image_url" then
          local imgObj = JSONObject()
          imgObj.put("url", item.image_url.url)
          itemObj.put("image_url", imgObj)
        end
        contentArr.put(itemObj)
      end
      msgObj.put("content", contentArr)
    end
    messagesArray.put(msgObj)
  end
  jsonPayload.put("messages", messagesArray)

  local payloadStr = jsonPayload.toString()
  local endpoint = "https://api.groq.com/openai/v1/chat/completions"

  local keysTriedCount = 0
  local totalKeys = #keyList

  -- Jika seluruh kunci akhirnya gagal, buang pesan pengguna yang sudah
  -- terlanjur dimasukkan ke riwayat supaya percakapan tidak menyimpan
  -- pertanyaan tanpa jawaban.
  local function dropPendingUserMessage()
    if #chatHistory > 0 and chatHistory[#chatHistory].role == "user" then
      table.remove(chatHistory, #chatHistory)
    end
  end

  local function executeWithKey()
    local currentItem = keyList[currentKeyIndex]
    local activeKey = currentItem.key
    local keyLabel = currentItem.name

    local headerMap = HashMap()
    headerMap.put("Content-Type", "application/json; charset=UTF-8")
    headerMap.put("Authorization", "Bearer " .. activeKey)

    local maxRetries = 2
    local attempt = 0

    local function switchToNextKey(reasonText)
      keysTriedCount = keysTriedCount + 1
      if keysTriedCount < totalKeys then
        currentKeyIndex = (currentKeyIndex % totalKeys) + 1
        local nextItem = keyList[currentKeyIndex]
        service.speak(reasonText .. " Beralih ke " .. nextItem.name .. "...")
        mainHandler.postDelayed(Runnable{
          run = function()
            executeWithKey()
          end
        }, 500)
      else
        dropPendingUserMessage()
        onComplete(false, "Semua kunci API (" .. totalKeys .. " kunci) telah mencapai limit token/kuota atau gagal diproses.")
      end
    end

    local function executeRequest()
      attempt = attempt + 1

      -- Penanda agar hasil (baik dari respon asli maupun dari watchdog
      -- timeout 15 detik) hanya diproses SATU KALI. Ini mencegah pesan
      -- ganda / logika ganda jika respon lambat tetap datang setelah
      -- timeout sudah dianggap gagal.
      local requestSettled = false

      local function handleResult(code, content)
        if requestSettled then return end
        requestSettled = true

        mainHandler.post(Runnable{
          run = function()
            -- 1. Respon Sukses (HTTP 200)
            if code == 200 and content and #content > 0 then
              local ok = pcall(function()
                local resObj = JSONObject(content)
                local choices = resObj.optJSONArray("choices")
                if choices and choices.length() > 0 then
                  local choiceMsg = choices.getJSONObject(0).optJSONObject("message")
                  if choiceMsg then
                    local text = choiceMsg.optString("content")
                    table.insert(chatHistory, { role = "assistant", content = text })
                    onComplete(true, text)
                    return
                  end
                end
                error("Respon server kosong")
              end)
              if ok then return end
            end

            -- 1b. Ditandai timeout oleh watchdog 15 detik
            if code == -1 then
              switchToNextKey("Waktu tunggu " .. keyLabel .. " habis (lebih dari 15 detik tanpa respons).")
              return
            end

            -- 2. Permintaan tidak valid (400) — bukan masalah kuota, jadi
            -- jangan diperlakukan sebagai limit dan jangan diputar ke
            -- kunci lain (kunci lain akan gagal dengan alasan yang sama).
            if code == 400 then
              dropPendingUserMessage()
              local reason = "Permintaan ditolak oleh server (kode 400)."
              pcall(function()
                if content and content ~= "" then
                  local errObj = JSONObject(content).optJSONObject("error")
                  if errObj then
                    local msg = errObj.optString("message")
                    if msg and msg ~= "" then
                      reason = "Permintaan ditolak: " .. msg
                    end
                  end
                end
              end)
              onComplete(false, reason)
              return
            end

            -- 3. Deteksi Limit Token / Kuota Habis (429, 402, 401, atau
            -- pesan JSON spesifik — kata kunci sengaja tidak terlalu umum
            -- supaya tidak salah menganggap error lain sebagai limit).
            local isLimit = false
            if code == 429 or code == 402 or code == 401 then
              isLimit = true
            elseif content and content ~= "" then
              local lc = string.lower(tostring(content))
              if lc:find("rate_limit")
                or lc:find("rate limit")
                or lc:find("quota")
                or lc:find("insufficient_quota")
                or lc:find("resource_exhausted")
                or lc:find("exceeded your current quota")
                or lc:find("tokens per minute")
                or lc:find("requests per minute") then
                isLimit = true
              end
            end

            if isLimit then
              switchToNextKey("Token/kuota pada " .. keyLabel .. " telah habis atau limit.")
              return
            end

            -- 4. Error Jaringan Sementara (Retry sebelum pindah kunci)
            if attempt < maxRetries then
              requestSettled = false
              mainHandler.postDelayed(Runnable{
                run = function()
                  executeRequest()
                end
              }, 1500)
            else
              switchToNextKey("Koneksi gagal pada " .. keyLabel .. ".")
            end
          end
        })
      end

      -- ====================================================================
      -- WATCHDOG TIMEOUT 15 DETIK
      -- Jika dalam 15 detik belum ada respons sama sekali (baik lewat
      -- httpEngine.post maupun koneksi manual java.net), anggap permintaan
      -- ini gagal (kode -1) dan lanjut ke logika penanganan biasa
      -- (retry / pindah kunci cadangan) alih-alih diam menunggu selamanya.
      -- Mekanisme ini disamakan dengan skrip "Deskripsi kamera Groq".
      -- ====================================================================
      mainHandler.postDelayed(Runnable{
        run = function()
          handleResult(-1, nil)
        end
      }, REQUEST_TIMEOUT_MS)

      local httpEngine = http or Http
      local dispatched = false

      if httpEngine and httpEngine.post then
        local ok = pcall(function()
          httpEngine.post(endpoint, payloadStr, headerMap, function(code, content)
            handleResult(code, content)
          end)
        end)
        if ok then
          dispatched = true
        else
          ok = pcall(function()
            httpEngine.post(endpoint, payloadStr, "", "UTF-8", headerMap, function(code, content)
              handleResult(code, content)
            end)
          end)
          if ok then dispatched = true end
        end
      end

      if not dispatched then
        Thread(Runnable{
          run = function()
            local postData = String(payloadStr).getBytes("UTF-8")
            local resCode = 0
            local resContent = nil
            pcall(function()
              local url = URL(endpoint)
              local conn = url.openConnection()
              conn.setRequestMethod("POST")
              conn.setInstanceFollowRedirects(false)
              conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
              conn.setRequestProperty("Authorization", "Bearer " .. activeKey)
              conn.setDoOutput(true)
              conn.setDoInput(true)
              -- Batas koneksi & baca disesuaikan agar total tetap berada
              -- di sekitar batas watchdog 15 detik di atas.
              conn.setConnectTimeout(5000)
              conn.setReadTimeout(10000)

              local outStream = conn.getOutputStream()
              outStream.write(postData)
              outStream.flush()
              outStream.close()

              resCode = conn.getResponseCode()
              local stream = (resCode == 200) and conn.getInputStream() or conn.getErrorStream()
              if stream then
                local reader = BufferedReader(InputStreamReader(stream, "UTF-8"))
                local lines = {}
                local line = reader.readLine()
                while line ~= nil do
                  table.insert(lines, line)
                  line = reader.readLine()
                end
                reader.close()
                resContent = table.concat(lines, "\n")
              end
              conn.disconnect()
            end)

            handleResult(resCode, resContent)
          end
        }).start()
      end
    end

    executeRequest()
  end

  executeWithKey()
end

-- ====================================================================
-- DIALOG & ANTARMUKA PENGGUNA
-- ====================================================================
showChatDialog = function()
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(30, 20, 30, 20)

  local scrollView = ScrollView(service)
  local chatLog = TextView(service)
  chatLog.setTextSize(16)
  chatLog.setTextIsSelectable(true)

  local function refreshChatLog()
    local pieces = {}
    for _, msg in ipairs(chatHistory) do
      if msg.role == "assistant" then
        table.insert(pieces, msg.content)
      end
    end
    chatLog.setText(table.concat(pieces, "\n\n"))
  end
  refreshChatLog()

  local scrollParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1)
  scrollView.setLayoutParams(scrollParams)
  scrollView.addView(chatLog)
  layout.addView(scrollView)

  local actionBtnLayout = LinearLayout(service)
  actionBtnLayout.setOrientation(LinearLayout.HORIZONTAL)
  actionBtnLayout.setPadding(0, 10, 0, 10)

  local btnReadAgain = Button(service)
  btnReadAgain.setText("Baca Ulang")
  local btnReadParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1)
  btnReadAgain.setLayoutParams(btnReadParams)
  actionBtnLayout.addView(btnReadAgain)

  local btnCopy = Button(service)
  btnCopy.setText("Salin Teks")
  local btnCopyParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1)
  btnCopy.setLayoutParams(btnCopyParams)
  actionBtnLayout.addView(btnCopy)

  layout.addView(actionBtnLayout)

  local inputLayout = LinearLayout(service)
  inputLayout.setOrientation(LinearLayout.HORIZONTAL)

  local editMsg = EditText(service)
  editMsg.setHint("Tanyakan detail lainnya...")
  local editParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1)
  editMsg.setLayoutParams(editParams)
  inputLayout.addView(editMsg)

  local btnSend = Button(service)
  btnSend.setText("Kirim")
  inputLayout.addView(btnSend)
  layout.addView(inputLayout)

  local mode = getScanMode()
  local dialogTitle = "Hasil Deskripsi Layar"
  if mode == "text_ocr" then
    dialogTitle = "Hasil Pindai Teks Layar"
  elseif mode == "video_desc" then
    dialogTitle = "Hasil Deskripsi Video"
  end

  local builder = AlertDialog.Builder(service)
    .setTitle(dialogTitle)
    .setView(layout)
    .setNegativeButton("Pengaturan", function(dialog)
      dialog.dismiss()
      showMainMenu()
    end)
    .setPositiveButton("Tutup", nil)

  displayOverlayDialog(builder)

  btnReadAgain.setOnClickListener(function()
    if #chatHistory > 0 and chatHistory[#chatHistory].role == "assistant" then
      service.speak(chatHistory[#chatHistory].content)
    end
  end)

  btnCopy.setOnClickListener(function()
    local textToCopy = ""
    if #chatHistory > 0 and chatHistory[#chatHistory].role == "assistant" then
      textToCopy = chatHistory[#chatHistory].content
    end
    if textToCopy ~= "" then
      pcall(function()
        local clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE)
        local clip = ClipData.newPlainText("Teks Layar Groq", textToCopy)
        clipboard.setPrimaryClip(clip)
        service.speak("Hasil berhasil disalin.")
      end)
    end
  end)

  btnSend.setOnClickListener(function()
    local userQuery = tostring(editMsg.getText()):gsub("^%s*(.-)%s*$", "%1")
    if userQuery ~= "" then
      editMsg.setText("")
      service.speak("Memproses tanggapan...")
      sendGroqChat(userQuery, nil, function(success, reply)
        if not success then
          table.insert(chatHistory, {role = "assistant", content = "Gagal memproses pertanyaan: " .. reply})
        end
        refreshChatLog()
        service.speak(reply)
        scrollView.post(Runnable{ run = function() scrollView.fullScroll(ScrollView.FOCUS_DOWN) end })
      end)
    end
  end)
end

local function showSingleKeyEditDialog(title, prefKey, currentValue, isPrimary)
  local input = EditText(service)
  input.setSingleLine(true)

  if currentValue ~= "" then
    input.setText(currentValue)
    input.setHint("Kunci aktif tersimpan")
  else
    input.setText("")
    input.setHint(isPrimary and "Tempel kunci API utama di sini..." or "Tempel kunci API cadangan di sini...")
  end

  local builder = AlertDialog.Builder(service)
    .setTitle(title)
    .setView(input)
    .setPositiveButton("Simpan", function()
      local key = tostring(input.getText()):gsub("^%s*(.-)%s*$", "%1")
      if key ~= "" then
        sp.edit().putString(prefKey, key).apply()
        currentKeyIndex = 1
        service.speak(title .. " berhasil disimpan.")
      else
        sp.edit().remove(prefKey).apply()
        currentKeyIndex = 1
        service.speak(title .. " dikosongkan.")
      end
    end)
    .setNeutralButton("Hapus Kunci", function()
      sp.edit().remove(prefKey).apply()
      currentKeyIndex = 1
      service.speak(title .. " dihapus.")
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

showApiKeyDialog = function()
  local k1 = sp.getString("custom_api_key", "")
  local k2 = sp.getString("backup_api_key_1", "")
  local k3 = sp.getString("backup_api_key_2", "")
  local localKey = readLocalApiKeyFile()

  local s1 = (k1 ~= "") and "Kustom Tersimpan" or (localKey ~= "" and "Dari api_key.txt" or "Belum Diatur")
  local s2 = (k2 ~= "") and "Tersimpan" or "Kosong"
  local s3 = (k3 ~= "") and "Tersimpan" or "Kosong"

  local allKeys = getAvailableApiKeys()
  local activeKeyName = (allKeys[currentKeyIndex] and allKeys[currentKeyIndex].name) or "Belum ada kunci"

  local items = {
    "1. Kunci API Utama (" .. s1 .. ")",
    "2. Kunci Cadangan 1 (" .. s2 .. ")",
    "3. Kunci Cadangan 2 (" .. s3 .. ")",
    "4. Kembalikan Posisi ke Kunci Utama (Aktif: " .. activeKeyName .. ")",
    "5. Reset / Hapus Seluruh Kunci API"
  }

  local builder = AlertDialog.Builder(service)
    .setTitle("Pengaturan Kunci API (Utama & Cadangan)")
    .setItems(items, function(dialog, which)
      dialog.dismiss()
      if which == 0 then
        showSingleKeyEditDialog("Kunci API Utama", "custom_api_key", k1, true)
      elseif which == 1 then
        showSingleKeyEditDialog("Kunci Cadangan 1", "backup_api_key_1", k2, false)
      elseif which == 2 then
        showSingleKeyEditDialog("Kunci Cadangan 2", "backup_api_key_2", k3, false)
      elseif which == 3 then
        currentKeyIndex = 1
        service.speak("Indeks kunci aktif dikembalikan ke Kunci Utama.")
      elseif which == 4 then
        sp.edit().remove("custom_api_key").remove("backup_api_key_1").remove("backup_api_key_2").apply()
        currentKeyIndex = 1
        if readLocalApiKeyFile() ~= "" then
          service.speak("Kunci kustom dan cadangan dihapus. Kembali ke file api_key.txt bawaan.")
        else
          service.speak("Semua kunci API berhasil dihapus.")
        end
      end
    end)
    .setNegativeButton("Tutup", nil)

  displayOverlayDialog(builder)
end

-- Dialog untuk mengetik nama model secara manual (dipakai oleh opsi
-- "Kustom" di showModelDialog).
local function showCustomModelInputDialog()
  local input = EditText(service)
  input.setSingleLine(true)
  input.setText(getModelName())
  input.setHint("Contoh: qwen/qwen3.8-27b")

  local builder = AlertDialog.Builder(service)
    .setTitle("Model Kustom (Manual)")
    .setView(input)
    .setPositiveButton("Simpan", function()
      local m = tostring(input.getText()):gsub("^%s*(.-)%s*$", "%1")
      if m ~= "" then
        setModelName(m)
        service.speak("Model diatur ke " .. m)
      end
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

-- Dialog pemilihan model & mode reasoning. Sebelumnya getModelName()/
-- setModelName() sudah ada tapi tidak pernah dipakai oleh menu manapun,
-- sehingga pengguna tidak bisa mengganti model dari UI. Dialog ini
-- menutup celah tersebut.
showModelDialog = function()
  local currentModel = getModelName()
  local options = {}
  local selectedIndex = #knownVisionModels -- default ke "Kustom" jika tidak cocok
  for i, m in ipairs(knownVisionModels) do
    table.insert(options, m)
    if m == currentModel then
      selectedIndex = i - 1
    end
  end
  table.insert(options, "Kustom (ketik manual)...")
  if currentModel ~= "" then
    local found = false
    for _, m in ipairs(knownVisionModels) do
      if m == currentModel then found = true end
    end
    if not found then
      selectedIndex = #options - 1
    end
  end

  local builder = AlertDialog.Builder(service)
    .setTitle("Pilih Model Groq (Aktif: " .. currentModel .. ")")
    .setSingleChoiceItems(options, selectedIndex, function(dialog, which)
      dialog.dismiss()
      if which == #options - 1 then
        showCustomModelInputDialog()
      else
        local chosen = knownVisionModels[which + 1]
        setModelName(chosen)
        service.speak("Model diatur ke " .. chosen)
      end
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

local function showReasoningEffortDialog()
  local effortOptions = {
    "Instruct - Cepat & Langsung Jawab (Bawaan, disarankan)",
    "Rendah (low)",
    "Sedang (medium)",
    "Tinggi (high)",
    "Maksimum (xhigh) - Paling Lambat & Boros Token"
  }
  local effortValues = { "none", "low", "medium", "high", "xhigh" }

  local curEffort = getReasoningEffort()
  local selectedIndex = 0
  for i, v in ipairs(effortValues) do
    if v == curEffort then selectedIndex = i - 1 end
  end

  local builder = AlertDialog.Builder(service)
    .setTitle("Mode Reasoning Model")
    .setSingleChoiceItems(effortOptions, selectedIndex, function(dialog, which)
      dialog.dismiss()
      local chosen = effortValues[which + 1]
      setReasoningEffort(chosen)
      service.speak("Mode reasoning diatur ke " .. effortOptions[which + 1])
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

local function showScanModeDialog()
  local modeOptions = {
    "Deskripsi Layar (Foto Tunggal)",
    "Deskripsi Video (Kompilasi Kronologis 3 Frame)",
    "Pindai Teks Saja (Hanya Ekstrak Teks)"
  }

  local currentMode = getScanMode()
  local selectedIndex = 0
  if currentMode == "video_desc" then
    selectedIndex = 1
  elseif currentMode == "text_ocr" then
    selectedIndex = 2
  else
    selectedIndex = 0
  end

  local builder = AlertDialog.Builder(service)
    .setTitle("Pilih Mode Pemindaian")
    .setSingleChoiceItems(modeOptions, selectedIndex, function(dialog, which)
      dialog.dismiss()
      if which == 0 then
        setScanMode("visual_desc")
        service.speak("Mode Deskripsi Layar diaktifkan.")
      elseif which == 1 then
        setScanMode("video_desc")
        service.speak("Mode Deskripsi Video diaktifkan.")
      else
        setScanMode("text_ocr")
        service.speak("Mode Pindai Teks Saja diaktifkan.")
      end
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

local function showVideoDurationDialog()
  local durationOptions = {
    "10 Detik (Cepat & Ringkas)",
    "15 Detik (Sedang & Optimal)",
    "20 Detik (Lebih Lengkap)"
  }

  local curDur = getVideoDuration()
  local selectedIndex = 0
  if curDur == 10 then selectedIndex = 0
  elseif curDur == 15 then selectedIndex = 1
  elseif curDur == 20 then selectedIndex = 2
  end

  local builder = AlertDialog.Builder(service)
    .setTitle("Pilih Durasi Perekaman Video")
    .setSingleChoiceItems(durationOptions, selectedIndex, function(dialog, which)
      dialog.dismiss()
      if which == 0 then
        setVideoDuration(10)
        service.speak("Durasi video diatur ke 10 detik.")
      elseif which == 1 then
        setVideoDuration(15)
        service.speak("Durasi video diatur ke 15 detik.")
      elseif which == 2 then
        setVideoDuration(20)
        service.speak("Durasi video diatur ke 20 detik.")
      end
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

local function showResolutionDialog()
  local resolutionOptions = {
    "Paling Tinggi - Resolusi Asli Layar (Paling Tajam)",
    "Tinggi - 1080p (Sangat Tajam & Jelas)",
    "Sedang - 720p (Seimbang & Cepat - Bawaan)",
    "Rendah - 480p (Hemat Kuota & Super Cepat)"
  }

  local curRes = getResolutionMode()
  local selectedIndex = 2
  if curRes == "original" then selectedIndex = 0
  elseif curRes == "1080" then selectedIndex = 1
  elseif curRes == "720" then selectedIndex = 2
  elseif curRes == "480" then selectedIndex = 3
  end

  local builder = AlertDialog.Builder(service)
    .setTitle("Pilih Resolusi Screenshot")
    .setSingleChoiceItems(resolutionOptions, selectedIndex, function(dialog, which)
      dialog.dismiss()
      if which == 0 then
        setResolutionMode("original")
        service.speak("Resolusi Asli Layar diaktifkan.")
      elseif which == 1 then
        setResolutionMode("1080")
        service.speak("Resolusi Tinggi 1080p diaktifkan.")
      elseif which == 2 then
        setResolutionMode("720")
        service.speak("Resolusi Sedang 720p diaktifkan.")
      elseif which == 3 then
        setResolutionMode("480")
        service.speak("Resolusi Rendah 480p diaktifkan. Catatan: mode Pindai Teks tetap memakai ketajaman minimum setara 720p agar akurat.")
      end
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

local function showImageInstructionDialog()
  local input = EditText(service)
  input.setText(getImageInstruction())
  input.setMinLines(5)

  local builder = AlertDialog.Builder(service)
    .setTitle("Instruksi Deskripsi Layar")
    .setView(input)
    .setPositiveButton("Simpan", function()
      local newInst = tostring(input.getText()):gsub("^%s*(.-)%s*$", "%1")
      if newInst == "" then newInst = defaultImageInstruction end
      setImageInstruction(newInst)
      service.speak("Instruksi deskripsi layar berhasil disimpan.")
    end)
    .setNeutralButton("Reset Default", function()
      setImageInstruction(defaultImageInstruction)
      service.speak("Instruksi deskripsi layar dikembalikan ke default.")
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

local function showVideoInstructionDialog()
  local input = EditText(service)
  input.setText(getVideoInstruction())
  input.setMinLines(5)

  local builder = AlertDialog.Builder(service)
    .setTitle("Instruksi Deskripsi Video")
    .setView(input)
    .setPositiveButton("Simpan", function()
      local newInst = tostring(input.getText()):gsub("^%s*(.-)%s*$", "%1")
      if newInst == "" then newInst = defaultVideoInstruction end
      setVideoInstruction(newInst)
      service.speak("Instruksi deskripsi video berhasil disimpan.")
    end)
    .setNeutralButton("Reset Default", function()
      setVideoInstruction(defaultVideoInstruction)
      service.speak("Instruksi deskripsi video dikembalikan ke default.")
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

local function showTextInstructionDialog()
  local input = EditText(service)
  input.setText(getTextInstruction())
  input.setMinLines(5)

  local builder = AlertDialog.Builder(service)
    .setTitle("Instruksi Pindai Teks Saja")
    .setView(input)
    .setPositiveButton("Simpan", function()
      local newInst = tostring(input.getText()):gsub("^%s*(.-)%s*$", "%1")
      if newInst == "" then newInst = defaultTextInstruction end
      setTextInstruction(newInst)
      service.speak("Instruksi pindai teks berhasil disimpan.")
    end)
    .setNeutralButton("Reset Default", function()
      setTextInstruction(defaultTextInstruction)
      service.speak("Instruksi pindai teks dikembalikan ke default.")
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

showMainMenu = function()
  local currentKeyStatus = getActiveKeyStatusLabel()

  local modeLabels = {
    ["visual_desc"] = "Deskripsi Layar",
    ["video_desc"] = "Deskripsi Video",
    ["text_ocr"] = "Pindai Teks Saja"
  }
  local currentModeText = modeLabels[getScanMode()] or "Deskripsi Layar"
  local currentDurText = tostring(getVideoDuration()) .. " Detik"

  local resLabels = {
    ["original"] = "Asli Layar",
    ["1080"] = "1080p",
    ["720"] = "720p",
    ["480"] = "480p"
  }
  local currentResText = resLabels[getResolutionMode()] or "720p"
  local currentModelText = getModelName()
  local effortLabels = {
    ["none"] = "Instruct (cepat)",
    ["low"] = "Rendah",
    ["medium"] = "Sedang",
    ["high"] = "Tinggi",
    ["xhigh"] = "Maksimum"
  }
  local currentEffortText = effortLabels[getReasoningEffort()] or "Instruct (cepat)"

  local menuItems = {
    "1. Atur Kunci API Groq (Utama & Cadangan) (" .. currentKeyStatus .. ")",
    "2. Ganti Model Groq (Aktif: " .. currentModelText .. ")",
    "3. Mode Reasoning Model (Aktif: " .. currentEffortText .. ")",
    "4. Mode Pemindaian (Aktif: " .. currentModeText .. ")",
    "5. Durasi Perekaman Video (Aktif: " .. currentDurText .. ")",
    "6. Kualitas Resolusi Screenshot (Aktif: " .. currentResText .. ")",
    "7. Atur Instruksi Deskripsi Layar",
    "8. Atur Instruksi Deskripsi Video",
    "9. Atur Instruksi Pindai Teks",
    "10. Periksa Versi Baru"
  }

  local builder = AlertDialog.Builder(service)
    .setTitle("Pengaturan Deskripsi Layar Groq AI by Novan (v" .. CURRENT_VERSION .. ")")
    .setItems(menuItems, function(dialog, which)
      dialog.dismiss()
      if which == 0 then
        showApiKeyDialog()
      elseif which == 1 then
        showModelDialog()
      elseif which == 2 then
        showReasoningEffortDialog()
      elseif which == 3 then
        showScanModeDialog()
      elseif which == 4 then
        showVideoDurationDialog()
      elseif which == 5 then
        showResolutionDialog()
      elseif which == 6 then
        showImageInstructionDialog()
      elseif which == 7 then
        showVideoInstructionDialog()
      elseif which == 8 then
        showTextInstructionDialog()
      elseif which == 9 then
        checkAppUpdate(true)
      end
    end)
    .setNegativeButton("Tutup", nil)

  displayOverlayDialog(builder)
end

startScreenDescription = function()
  if #getAvailableApiKeys() == 0 then
    service.speak("Kunci API Groq belum ditemukan. Silakan atur kunci API atau buat file api_key.txt.")
    showApiKeyDialog()
    return
  end
  if Build.VERSION.SDK_INT < 30 then
    local errText = "Fitur tangkapan layar membutuhkan minimal Android 11."
    chatHistory = { {role = "assistant", content = errText} }
    service.speak(errText)
    showChatDialog()
    return
  end

  local scanMode = getScanMode()

  -- ==================================================================
  -- ALUR 1: MODE DESKRIPSI VIDEO (3 FRAME KRONOLOGIS VERTIKAL)
  -- ==================================================================
  if scanMode == "video_desc" then
    local dur = getVideoDuration()
    local interval = math.floor((dur * 1000) / 2)
    service.speak("Merekam video selama " .. tostring(dur) .. " detik...")

    local frames = {}
    local frameLimit = getVideoFrameLimit()

    -- Ambil Frame 1: Awal Pemutaran (Panel Atas)
    mainHandler.postDelayed(Runnable{
      run = function()
        captureSingleFrame(function(ok1, bmp1)
          if not ok1 or not bmp1 then
            local err = type(bmp1) == "string" and bmp1 or "Gagal mengambil frame awal video."
            chatHistory = { {role = "assistant", content = err} }
            service.speak(err)
            showChatDialog()
            return
          end
          -- Kecilkan frame SEGERA setelah ditangkap, sebelum digabung,
          -- supaya kanvas gabungan tidak pernah berukuran resolusi
          -- layar penuh x 3 (mencegah risiko kehabisan memori).
          bmp1 = downscaleBitmapToLimit(bmp1, frameLimit)
          table.insert(frames, bmp1)

          -- Ambil Frame 2: Pertengahan Pemutaran (Panel Tengah)
          mainHandler.postDelayed(Runnable{
            run = function()
              captureSingleFrame(function(ok2, bmp2)
                if not ok2 or not bmp2 then
                  local err = type(bmp2) == "string" and bmp2 or "Gagal mengambil frame tengah video."
                  chatHistory = { {role = "assistant", content = err} }
                  service.speak(err)
                  showChatDialog()
                  return
                end
                bmp2 = downscaleBitmapToLimit(bmp2, frameLimit)
                table.insert(frames, bmp2)

                -- Ambil Frame 3: Akhir Pemutaran (Panel Bawah)
                mainHandler.postDelayed(Runnable{
                  run = function()
                    captureSingleFrame(function(ok3, bmp3)
                      if not ok3 or not bmp3 then
                        local err = type(bmp3) == "string" and bmp3 or "Gagal mengambil frame akhir video."
                        chatHistory = { {role = "assistant", content = err} }
                        service.speak(err)
                        showChatDialog()
                        return
                      end
                      bmp3 = downscaleBitmapToLimit(bmp3, frameLimit)
                      table.insert(frames, bmp3)

                      -- Jaga-jaga: jika orientasi/ukuran layar berubah di
                      -- tengah perekaman, lebar antar-frame bisa berbeda
                      -- dan akan merusak susunan kanvas gabungan. Batalkan
                      -- dengan pesan yang jelas alih-alih menghasilkan
                      -- gambar gabungan yang salah tanpa peringatan.
                      if frames[1].getWidth() ~= frames[2].getWidth()
                        or frames[1].getWidth() ~= frames[3].getWidth() then
                        pcall(function() frames[1].recycle() end)
                        pcall(function() frames[2].recycle() end)
                        pcall(function() frames[3].recycle() end)
                        local errDim = "Ukuran layar berubah saat perekaman video. Coba lagi tanpa memutar layar."
                        chatHistory = { {role = "assistant", content = errDim} }
                        service.speak(errDim)
                        showChatDialog()
                        return
                      end

                      service.speak("Menganalisis video dengan Groq...")

                      Thread(Runnable{
                        run = function()
                          local base64Screen = nil
                          pcall(function()
                            local w = frames[1].getWidth()
                            local h1 = frames[1].getHeight()
                            local h2 = frames[2].getHeight()
                            local h3 = frames[3].getHeight()
                            local totalH = h1 + h2 + h3

                            local stitched = Bitmap.createBitmap(w, totalH, Bitmap.Config.ARGB_8888)
                            local canvas = Canvas(stitched)
                            canvas.drawBitmap(frames[1], 0, 0, nil)
                            canvas.drawBitmap(frames[2], 0, h1, nil)
                            canvas.drawBitmap(frames[3], 0, h1 + h2, nil)

                            pcall(function() frames[1].recycle() end)
                            pcall(function() frames[2].recycle() end)
                            pcall(function() frames[3].recycle() end)

                            base64Screen = bitmapToBase64(stitched, true, false)
                          end)

                          mainHandler.post(Runnable{
                            run = function()
                              if base64Screen then
                                chatHistory = {}
                                currentSysInstruction = getVideoInstruction()
                                local queryText = "Deskripsikan alur cerita kronologis dari kompilasi video 3 panel vertikal ini secara lengkap dan runtut."
                                sendGroqChat(queryText, base64Screen, function(success, reply)
                                  if success then
                                    service.speak(reply)
                                    showChatDialog()
                                  else
                                    local errMsg = "Gagal memproses video: " .. reply
                                    table.insert(chatHistory, {role = "assistant", content = errMsg})
                                    service.speak(errMsg)
                                    showChatDialog()
                                  end
                                end)
                              else
                                local errBmp = "Gagal menggabungkan panel video."
                                chatHistory = { {role = "assistant", content = errBmp} }
                                service.speak(errBmp)
                                showChatDialog()
                              end
                            end
                          })
                        end
                      }).start()
                    end)
                  end
                }, interval)
              end)
            end
          }, interval)
        end)
      end
    }, 250)
    return
  end

  -- ==================================================================
  -- ALUR 2: MODE DESKRIPSI LAYAR BIASA & PINDAI TEKS
  -- ==================================================================
  local isTextMode = (scanMode == "text_ocr")
  service.speak(isTextMode and "Memindai teks pada layar..." or "Memindai layar...")

  mainHandler.postDelayed(Runnable{
    run = function()
      captureSingleFrame(function(ok, bitmap)
        if not ok or not bitmap then
          local errShot = (type(bitmap) == "string" and bitmap) or "Gagal mengambil tangkapan layar."
          chatHistory = { {role = "assistant", content = errShot} }
          service.speak(errShot)
          showChatDialog()
          return
        end

        Thread(Runnable{
          run = function()
            local base64Screen = bitmapToBase64(bitmap, false, isTextMode)
            mainHandler.post(Runnable{
              run = function()
                if base64Screen then
                  service.speak(isTextMode and "Mengekstrak teks..." or "Menganalisis dengan Groq...")
                  chatHistory = {}

                  local queryText = ""
                  if isTextMode then
                    currentSysInstruction = getTextInstruction()
                    queryText = "Tuliskan seluruh teks asli yang terlihat di layar ini persis apa adanya tanpa kata pengantar atau deskripsi visual apa pun."
                  else
                    currentSysInstruction = getImageInstruction()
                    queryText = "Deskripsikan konten utama pada layar ini secara terperinci tanpa menyebutkan bilah status atas maupun bilah navigasi bawah."
                  end

                  sendGroqChat(queryText, base64Screen, function(success, reply)
                    if success then
                      service.speak(reply)
                      showChatDialog()
                    else
                      local errMsg = "Gagal memproses layar: " .. reply
                      table.insert(chatHistory, {role = "assistant", content = errMsg})
                      service.speak(errMsg)
                      showChatDialog()
                    end
                  end)
                else
                  local errBmp = "Gagal memproses bitmap layar."
                  chatHistory = { {role = "assistant", content = errBmp} }
                  service.speak(errBmp)
                  showChatDialog()
                end
              end
            })
          end
        }).start()
      end)
    end
  }, 250)
end

-- ====================================================================
-- EKSEKUSI AWAL
-- ====================================================================
startScreenDescription()

return true