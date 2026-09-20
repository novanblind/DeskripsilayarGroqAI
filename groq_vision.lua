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
local CURRENT_VERSION = "2.0.5"
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/novanblind/DeskripsilayarGroqAI/main/groq_vision.lua"

local defaultApiKey = ""

local defaultImageInstruction = [[Deskripsikan gambar atau tampilan layar secara jelas, natural, dan profesional dalam bahasa Indonesia. Susun narasi visual yang mengalir dari elemen paling dominan ke objek, karakter, lingkungan, dan detail sekitarnya. Jelaskan warna, bentuk, ukuran, tekstur, posisi, pencahayaan, suasana, komposisi, serta hubungan antarelemen tanpa berlebihan atau mengarang informasi. Abaikan elemen antarmuka ponsel yang tidak relevan, seperti indikator sinyal, baterai, waktu, notifikasi, atau ikon sistem lainnya, kecuali jika secara khusus diminta untuk menjelaskannya.

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
-- MANAJEMEN PENGATURAN & KUNCI API
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

local function getCustomApiKey()
  local k = sp.getString("api_key", "")
  if k ~= nil and k ~= "" then return k end
  return ""
end

local function getApiKey()
  local customKey = getCustomApiKey()
  if customKey ~= "" then return customKey end

  local fileKey = readLocalApiKeyFile()
  if fileKey ~= "" then return fileKey end

  return defaultApiKey
end

local function setApiKey(k)
  if k and k ~= "" then
    sp.edit().putString("api_key", k).apply()
  else
    sp.edit().remove("api_key").apply()
  end
end

local function getModelName() return sp.getString("model_name", "qwen/qwen3.8-27b") end
local function setModelName(m) sp.edit().putString("model_name", m).apply() end

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
local function bitmapToBase64(bitmap, isVideoMode)
  local resMode = getResolutionMode()
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

local function captureSingleFrame(callback)
  pcall(function()
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
end

-- ====================================================================
-- GROQ API ASINKRON BEBAS KUNCI LUA
-- ====================================================================
local function sendGroqChat(userText, mediaData, onComplete)
  local apiKey = getApiKey()
  if apiKey == "" then
    onComplete(false, "Kunci API Groq belum ditemukan. Silakan atur di menu pengaturan.")
    showApiKeyDialog()
    return
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

  local jsonPayload = JSONObject()
  jsonPayload.put("model", activeModel)
  jsonPayload.put("temperature", 0.1)
  jsonPayload.put("max_tokens", 800)

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

  local headerMap = HashMap()
  headerMap.put("Content-Type", "application/json; charset=UTF-8")
  headerMap.put("Authorization", "Bearer " .. apiKey)

  local maxRetries = 3
  local attempt = 0

  local function executeRequest()
    attempt = attempt + 1

    local function handleResult(code, content)
      mainHandler.post(Runnable{
        run = function()
          if code == 200 and content and #content > 0 then
            local ok, parseErr = pcall(function()
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

          if attempt < maxRetries then
            mainHandler.postDelayed(Runnable{
              run = function()
                executeRequest()
              end
            }, 1500)
          else
            local errMsg = "Gagal memproses permintaan setelah " .. attempt .. "x percobaan."
            if content then
              pcall(function()
                local errObj = JSONObject(content).optJSONObject("error")
                if errObj then
                  errMsg = errObj.optString("message") .. " (" .. attempt .. "x gagal)"
                end
              end)
            end
            onComplete(false, errMsg)
          end
        end
      })
    end

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
            conn.setRequestProperty("Authorization", "Bearer " .. apiKey)
            conn.setDoOutput(true)
            conn.setDoInput(true)
            conn.setConnectTimeout(12000)
            conn.setReadTimeout(25000)

            local os = conn.getOutputStream()
            os.write(postData)
            os.flush()
            os.close()

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

showApiKeyDialog = function()
  local customKey = getCustomApiKey()
  local input = EditText(service)
  input.setText(customKey ~= "" and customKey or "")

  local defaultExists = (readLocalApiKeyFile() ~= "" or defaultApiKey ~= "")
  if defaultExists and customKey == "" then
    input.setHint("Kunci bawaan aktif. Tempel kunci baru jika ingin mengganti...")
  else
    input.setHint("Tempel Kunci API Groq (gsk_...) di sini...")
  end
  input.setSingleLine(true)

  local builder = AlertDialog.Builder(service)
    .setTitle("Atur Kunci API Groq")
    .setView(input)
    .setPositiveButton("Simpan", function()
      local key = tostring(input.getText()):gsub("^%s*(.-)%s*$", "%1")
      if key ~= "" then
        setApiKey(key)
        service.speak("Kunci API kustom berhasil disimpan.")
      else
        setApiKey("")
        service.speak("Kunci kustom dihapus, kembali ke kunci bawaan.")
      end
    end)
    .setNeutralButton("Reset Bawaan", function()
      setApiKey("")
      local defaultKey = readLocalApiKeyFile()
      if defaultKey ~= "" or defaultApiKey ~= "" then
        service.speak("Kunci API dikembalikan ke setelan bawaan.")
      else
        service.speak("Kunci API di-reset. Pastikan file api_key.txt terisi kunci bawaan.")
      end
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
        service.speak("Resolusi Rendah 480p diaktifkan.")
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
  local customKey = getCustomApiKey()
  local currentKeyStatus = "Belum Diatur"
  if customKey ~= "" then
    currentKeyStatus = "Kustom Terpasang"
  elseif getApiKey() ~= "" then
    currentKeyStatus = "Bawaan Aktif"
  end

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

  local menuItems = {
    "1. Atur Kunci API Groq (" .. currentKeyStatus .. ")",
    "2. Mode Pemindaian (Aktif: " .. currentModeText .. ")",
    "3. Durasi Perekaman Video (Aktif: " .. currentDurText .. ")",
    "4. Kualitas Resolusi Screenshot (Aktif: " .. currentResText .. ")",
    "5. Atur Instruksi Deskripsi Layar",
    "6. Atur Instruksi Deskripsi Video",
    "7. Atur Instruksi Pindai Teks",
    "8. Periksa Versi Baru"
  }

  local builder = AlertDialog.Builder(service)
    .setTitle("Pengaturan Deskripsi Layar Groq AI by Novan (v" .. CURRENT_VERSION .. ")")
    .setItems(menuItems, function(dialog, which)
      dialog.dismiss()
      if which == 0 then
        showApiKeyDialog()
      elseif which == 1 then
        showScanModeDialog()
      elseif which == 2 then
        showVideoDurationDialog()
      elseif which == 3 then
        showResolutionDialog()
      elseif which == 4 then
        showImageInstructionDialog()
      elseif which == 5 then
        showVideoInstructionDialog()
      elseif which == 6 then
        showTextInstructionDialog()
      elseif which == 7 then
        checkAppUpdate(true)
      end
    end)
    .setNegativeButton("Tutup", nil)

  displayOverlayDialog(builder)
end

startScreenDescription = function()
  if getApiKey() == "" then
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

    -- Ambil Frame 1: Awal Pemutaran (Panel Atas)
    mainHandler.postDelayed(Runnable{
      run = function()
        captureSingleFrame(function(ok1, bmp1)
          if not ok1 or not bmp1 then
            local err = "Gagal mengambil frame awal video."
            chatHistory = { {role = "assistant", content = err} }
            service.speak(err)
            showChatDialog()
            return
          end
          table.insert(frames, bmp1)

          -- Ambil Frame 2: Pertengahan Pemutaran (Panel Tengah)
          mainHandler.postDelayed(Runnable{
            run = function()
              captureSingleFrame(function(ok2, bmp2)
                if not ok2 or not bmp2 then
                  local err = "Gagal mengambil frame tengah video."
                  chatHistory = { {role = "assistant", content = err} }
                  service.speak(err)
                  showChatDialog()
                  return
                end
                table.insert(frames, bmp2)

                -- Ambil Frame 3: Akhir Pemutaran (Panel Bawah)
                mainHandler.postDelayed(Runnable{
                  run = function()
                    captureSingleFrame(function(ok3, bmp3)
                      if not ok3 or not bmp3 then
                        local err = "Gagal mengambil frame akhir video."
                        chatHistory = { {role = "assistant", content = err} }
                        service.speak(err)
                        showChatDialog()
                        return
                      end
                      table.insert(frames, bmp3)

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

                            base64Screen = bitmapToBase64(stitched, true)
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
          local errShot = bitmap or "Gagal mengambil tangkapan layar."
          chatHistory = { {role = "assistant", content = errShot} }
          service.speak(errShot)
          showChatDialog()
          return
        end

        Thread(Runnable{
          run = function()
            local base64Screen = bitmapToBase64(bitmap, false)
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

mainHandler.postDelayed(Runnable{
  run = function()
    checkAppUpdate(false)
  end
}, 1000)

return true
