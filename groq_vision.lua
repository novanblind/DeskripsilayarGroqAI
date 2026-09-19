require "import"
import "android.graphics.Bitmap"
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
local CURRENT_VERSION = "2.0.2"
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/novanblind/DeskripsilayarGroqAI/main/groq_vision.lua"

local defaultApiKey = ""

local defaultImageInstruction = [[Deskripsikan gambar atau tampilan layar secara jelas, natural, dan profesional dalam bahasa Indonesia. Susun narasi visual yang mengalir dari elemen paling dominan ke objek, karakter, lingkungan, dan detail sekitarnya. Jelaskan warna, bentuk, ukuran, tekstur, posisi, pencahayaan, suasana, komposisi, serta hubungan antarelemen tanpa berlebihan atau mengarang informasi. Abaikan elemen antarmuka ponsel yang tidak relevan, seperti indikator sinyal, baterai, waktu, notifikasi, atau ikon sistem lainnya, kecuali jika secara khusus diminta untuk menjelaskannya.

Jika terdapat manusia atau karakter, gambarkan penampilan, pakaian, ekspresi, arah pandangan, gestur, dan kesan emosional yang tampak. Jelaskan pula kedalaman ruang, objek di depan, tengah, dan belakang, serta cara komposisi mengarahkan perhatian.

Jika gambar berisi surat, dokumen, formulir, poster, papan, atau teks lainnya, bacakan dan transkripsikan seluruh teks yang terlihat secara akurat. Pertahankan urutan pembacaan sesuai tata letak gambar.

Jangan gunakan pembuka umum seperti 'Gambar ini menunjukkan...', penomoran, bullet point, subjudul, atau kategori. Dasarkan setiap pernyataan pada hal yang benar-benar terlihat; nyatakan ketidakpastian jika diperlukan. Pastikan isi surat atau dokumen disampaikan secara lengkap sebelum memberikan deskripsi visual dan kesan suasana keseluruhan.]]

local defaultTextInstruction = [[Ekstrak dan transkripsikan seluruh teks yang terlihat pada tampilan layar ini secara akurat, lengkap, dan berurutan dari atas ke bawah sesuai tata letak aslinya.

DILARANG memberikan kata pengantar, penjelasan, pembuka (seperti "Teks pada layar adalah:", "Berikut teksnya:"), penutup, ataupun deskripsi visual mengenai elemen layar.

Tampilkan HANYA teks asli yang tertulis di layar persis apa adanya tanpa basa-basi. Jika tidak ada teks sama sekali yang terlihat, tuliskan: Tidak ada teks yang terdeteksi.]]

local sp = service.getSharedPreferences("groq_vision_desc_config", Context.MODE_PRIVATE)

-- ====================================================================
-- MANAJEMEN FILE LOKAL & KUNCI API
-- ====================================================================
local function getScriptFilePath()
  local src = debug.getinfo(1, "S").source
  if src and src:sub(1, 1) == "@" then
    return src:sub(2)
  end
  local fallbackPaths = {
    "/sdcard/jieshuo/plugin/Deskripsi Layar Groq/main.lua",
    "/sdcard/jieshuo/plugin/DeskripsilayarGroqAI/groq_vision.lua",
    "/sdcard/jieshuo/plugin/DeskripsiLayarGroq/main.lua"
  }
  for _, path in ipairs(fallbackPaths) do
    if File(path).exists() then return path end
  end
  return nil
end

local function getScriptDir()
  local path = getScriptFilePath()
  if path then
    return path:match("(.*/)")
  end
  return "/sdcard/jieshuo/plugin/Deskripsi Layar Groq/"
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

local function getResolutionMode() return sp.getString("scan_resolution", "720") end
local function setResolutionMode(r) sp.edit().putString("scan_resolution", r).apply() end

local function getImageInstruction() return sp.getString("custom_instruction", defaultImageInstruction) end
local function setImageInstruction(i) sp.edit().putString("custom_instruction", i).apply() end

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
-- AUTO-UPDATE SENYAP DI LATAR BELAKANG
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

checkAppUpdate = function()
  if GITHUB_RAW_URL:find("USERNAME/REPO_NAME") then return end
  local fetchUrl = GITHUB_RAW_URL .. "?t=" .. tostring(os.time())

  if http and http.get then
    http.get(fetchUrl, function(code, content)
      if code == 200 and content and #content >= 200 then
        local remoteVersion = content:match('local%s+CURRENT_VERSION%s*=%s*["\']([^"\']+)["\']')
        if remoteVersion and isNewerVersion(remoteVersion, CURRENT_VERSION) then
          local localPath = getScriptFilePath()
          if localPath then saveNewScript(content, localPath) end
        end
      end
    end)
  end
end

-- ====================================================================
-- PENGOLAHAN GAMBAR (RESOLUSI DAPAT DIATUR)
-- ====================================================================
local function bitmapToBase64(bitmap)
  local resMode = getResolutionMode()
  local targetQuality = 75
  local limit = 720

  if resMode == "original" then
    limit = 0
    targetQuality = 85
  elseif resMode == "1080" then
    limit = 1080
    targetQuality = 80
  elseif resMode == "720" then
    limit = 720
    targetQuality = 75
  elseif resMode == "480" then
    limit = 480
    targetQuality = 70
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

-- ====================================================================
-- GROQ API ASINKRON BEBAS KUNCI LUA (KURSOR BEBAS BERGERAK)
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
  jsonPayload.put("max_tokens", 1500)

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

  -- Konversi Header ke HashMap Java murni agar dapat diproses oleh engine C/Java tanpa error tipe data
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

          -- Pengulangan otomatis hingga 3 kali
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

    -- Panggil Http.post bawaan Java yang sepenuhnya non-blocking terhadap UI
    local httpEngine = http or Http
    local dispatched = false

    if httpEngine and httpEngine.post then
      -- Signature 1: (url, data, headerMap, callback)
      local ok = pcall(function()
        httpEngine.post(endpoint, payloadStr, headerMap, function(code, content)
          handleResult(code, content)
        end)
      end)
      if ok then
        dispatched = true
      else
        -- Signature 2: (url, data, cookie, charset, headerMap, callback)
        ok = pcall(function()
          httpEngine.post(endpoint, payloadStr, "", "UTF-8", headerMap, function(code, content)
            handleResult(code, content)
          end)
        end)
        if ok then dispatched = true end
      end
    end

    -- Fallback aman jika engine http.post tidak terpasang
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

  local dialogTitle = (getScanMode() == "text_ocr") and "Hasil Pindai Teks Layar" or "Hasil Deskripsi Layar"

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
    "Deskripsi Layar (Visual, Objek & Teks)",
    "Pindai Teks Saja (Hanya Ekstrak Teks Tanpa Basa-Basi)"
  }

  local currentMode = getScanMode()
  local selectedIndex = (currentMode == "text_ocr") and 1 or 0

  local builder = AlertDialog.Builder(service)
    .setTitle("Pilih Mode Pemindaian")
    .setSingleChoiceItems(modeOptions, selectedIndex, function(dialog, which)
      dialog.dismiss()
      if which == 0 then
        setScanMode("visual_desc")
        service.speak("Mode Deskripsi Layar diaktifkan.")
      else
        setScanMode("text_ocr")
        service.speak("Mode Pindai Teks Saja diaktifkan.")
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

  local currentModeText = (getScanMode() == "text_ocr") and "Pindai Teks Saja" or "Deskripsi Layar"

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
    "3. Kualitas Resolusi Screenshot (Aktif: " .. currentResText .. ")",
    "4. Atur Instruksi Deskripsi Layar",
    "5. Atur Instruksi Pindai Teks"
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
        showResolutionDialog()
      elseif which == 3 then
        showImageInstructionDialog()
      elseif which == 4 then
        showTextInstructionDialog()
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

  local isTextMode = (getScanMode() == "text_ocr")
  service.speak(isTextMode and "Memindai teks pada layar..." or "Memindai layar...")

  mainHandler.postDelayed(Runnable{
    run = function()
      pcall(function()
        service.takeScreenshot(Display.DEFAULT_DISPLAY, service.getMainExecutor(), TakeScreenshotCallback{
          onSuccess = function(screenshotResult)
            Thread(Runnable{
              run = function()
                local base64Screen = nil
                pcall(function()
                  local hwBuffer = screenshotResult.getHardwareBuffer()
                  local colorSpace = screenshotResult.getColorSpace()
                  local bitmap = Bitmap.wrapHardwareBuffer(hwBuffer, colorSpace)
                  if bitmap then
                    base64Screen = bitmapToBase64(bitmap)
                  end
                  if hwBuffer then hwBuffer.close() end
                end)

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
          end,
          onFailure = function(errorCode)
            mainHandler.post(Runnable{
              run = function()
                local errShot = "Gagal mengambil tangkapan layar. Kode: " .. tostring(errorCode)
                chatHistory = { {role = "assistant", content = errShot} }
                service.speak(errShot)
                showChatDialog()
              end
            })
          end
        })
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
    checkAppUpdate()
  end
}, 1000)

return true
