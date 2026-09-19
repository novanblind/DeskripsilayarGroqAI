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

local mainHandler = Handler(Looper.getMainLooper())

-- ====================================================================
-- KONFIGURASI VERSI & GITHUB AUTO-UPDATE
-- ====================================================================
local CURRENT_VERSION = "2.0.0"

-- URL RAW GitHub repositori Anda
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/novanblind/DeskripsilayarGroqAI/main/groq_vision.lua"

-- Kunci API Bawaan
local defaultApiKey = "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"

-- Default system instruction untuk deskripsi layar tunggal
local defaultImageInstruction = [[Deskripsikan gambar atau tampilan layar secara jelas, natural, dan profesional dalam bahasa Indonesia. Susun narasi visual yang mengalir dari elemen paling dominan ke objek, karakter, lingkungan, dan detail sekitarnya. Jelaskan warna, bentuk, ukuran, tekstur, posisi, pencahayaan, suasana, komposisi, serta hubungan antarelemen tanpa berlebihan atau mengarang informasi. Abaikan elemen antarmuka ponsel yang tidak relevan, seperti indikator sinyal, baterai, waktu, notifikasi, atau ikon sistem lainnya, kecuali jika secara khusus diminta untuk menjelaskannya.

Jika terdapat manusia atau karakter, gambarkan penampilan, pakaian, ekspresi, arah pandangan, gestur, dan kesan emosional yang tampak. Jelaskan pula kedalaman ruang, objek di depan, tengah, dan belakang, serta cara komposisi mengarahkan perhatian.

Jika gambar berisi surat, dokumen, formulir, poster, papan, atau teks lainnya, bacakan dan transkripsikan seluruh teks yang terlihat secara akurat. Pertahankan urutan pembacaan sesuai tata letak gambar.

Jangan gunakan pembuka umum seperti 'Gambar ini menunjukkan...', penomoran, bullet point, subjudul, atau kategori. Dasarkan setiap pernyataan pada hal yang benar-benar terlihat; nyatakan ketidakpastian jika diperlukan. Pastikan isi surat atau dokumen disampaikan secara lengkap sebelum memberikan deskripsi visual dan kesan suasana keseluruhan.]]

-- Daftar Model Groq Vision Aktif
local availableModels = {
  "qwen/qwen3.8-27b"
}

-- SharedPreferences Groq khusus Deskripsi Visual
local sp = service.getSharedPreferences("groq_vision_desc_config", Context.MODE_PRIVATE)

local function getApiKey()
  local key = sp.getString("api_key", defaultApiKey)
  if key == nil or key == "" then return defaultApiKey end
  return key
end

local function setApiKey(k) sp.edit().putString("api_key", k).apply() end

local function getModelName() return sp.getString("model_name", "qwen/qwen3.8-27b") end
local function setModelName(m) sp.edit().putString("model_name", m).apply() end

-- Mode bawaan disetel ke "direct_image" (Mode Langsung)
local function getAppMode() return sp.getString("app_mode", "direct_image") end
local function setAppMode(m) sp.edit().putString("app_mode", m).apply() end

local function getImageInstruction() return sp.getString("custom_instruction", defaultImageInstruction) end
local function setImageInstruction(i) sp.edit().putString("custom_instruction", i).apply() end

-- Helper overlay dialog
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
-- MODUL SISTEM AUTO-UPDATE
-- ====================================================================
local function getScriptFilePath()
  local src = debug.getinfo(1, "S").source
  if src and src:sub(1, 1) == "@" then
    return src:sub(2)
  end
  -- Fallback jika path tidak terbaca langsung dari debug
  local fallbackPaths = {
    "/sdcard/jieshuo/plugin/Deskripsi Layar Groq/main.lua",
    "/sdcard/jieshuo/plugin/DeskripsilayarGroqAI/groq_vision.lua"
  }
  for _, path in ipairs(fallbackPaths) do
    if File(path).exists() then return path end
  end
  return nil
end

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

checkAppUpdate = function(isManual)
  if GITHUB_RAW_URL:find("USERNAME/REPO_NAME") then
    if isManual then
      service.speak("URL GitHub belum dikonfigurasi. Silakan ubah variabel GITHUB_RAW_URL pada script.")
    end
    return
  end

  if isManual then
    service.speak("Memeriksa pembaruan...")
  end

  Thread(Runnable{
    run = function()
      local conn = nil
      local reader = nil
      local remoteContent = nil
      local isSuccess = false
      local errDetail = ""

      pcall(function()
        -- Tambahkan parameter waktu (?t=...) agar selalu mengambil revisi terbaru (anti-cache CDN)
        local fetchUrl = GITHUB_RAW_URL .. "?t=" .. tostring(os.time())
        local url = URL(fetchUrl)
        conn = url.openConnection()
        conn.setRequestMethod("GET")
        conn.setInstanceFollowRedirects(true)
        conn.setRequestProperty("User-Agent", "Mozilla/5.0")
        conn.setConnectTimeout(10000)
        conn.setReadTimeout(15000)

        if conn.getResponseCode() == 200 then
          reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
          local lines = {}
          local line = reader.readLine()
          while line ~= nil do
            table.insert(lines, line)
            line = reader.readLine()
          end
          reader.close()
          remoteContent = table.concat(lines, "\n")
          isSuccess = true
        else
          errDetail = "HTTP Code: " .. tostring(conn.getResponseCode())
        end
      end)

      if reader then pcall(function() reader.close() end) end
      if conn then pcall(function() conn.disconnect() end) end

      mainHandler.post(Runnable{
        run = function()
          if not isSuccess or not remoteContent then
            if isManual then
              service.speak("Gagal memeriksa pembaruan. " .. errDetail)
            end
            return
          end

          local remoteVersion = remoteContent:match('local%s+CURRENT_VERSION%s*=%s*["\']([^"\']+)["\']')
            or remoteContent:match('@version%s+([%d%.]+)')

          if remoteVersion and isNewerVersion(remoteVersion, CURRENT_VERSION) then
            service.speak("Pembaruan versi " .. remoteVersion .. " tersedia.")
            
            local builder = AlertDialog.Builder(service)
              .setTitle("Pembaruan Tersedia")
              .setMessage("Versi baru (" .. remoteVersion .. ") telah dirilis di GitHub.\nVersi saat ini: " .. CURRENT_VERSION .. "\n\nPerbarui script sekarang?")
              .setPositiveButton("Perbarui", function()
                local localPath = getScriptFilePath()
                if localPath and saveNewScript(remoteContent, localPath) then
                  service.speak("Pembaruan berhasil dipasang. Silakan jalankan ulang plugin.")
                  local successDialog = AlertDialog.Builder(service)
                    .setTitle("Sukses")
                    .setMessage("Script berhasil diperbarui ke versi " .. remoteVersion .. "!\nSilakan jalankan ulang script atau buka kembali menu untuk memuat fitur terbaru.")
                    .setPositiveButton("OK", nil)
                  displayOverlayDialog(successDialog)
                else
                  service.speak("Gagal menyimpan file script baru ke penyimpanan lokal.")
                end
              end)
              .setNegativeButton("Nanti", nil)
            displayOverlayDialog(builder)
          else
            if isManual then
              service.speak("Script sudah menggunakan versi terbaru (v" .. CURRENT_VERSION .. ").")
            end
          end
        end
      })
    end
  }).start()
end

-- ====================================================================
-- MODUL PENGOLAHAN GAMBAR & GROQ API
-- ====================================================================
local function bitmapToBase64(bitmap, quality)
  local targetQuality = quality or 90
  local targetBitmap = bitmap
  local needRecycleTarget = false
  
  if bitmap.getConfig() == Bitmap.Config.HARDWARE then
    targetBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
    needRecycleTarget = true
  end

  local baos = ByteArrayOutputStream()
  targetBitmap.compress(Bitmap.CompressFormat.JPEG, targetQuality, baos)
  local bytes = baos.toByteArray()
  baos.close()
  local base64Str = Base64.encodeToString(bytes, Base64.NO_WRAP)
  
  if needRecycleTarget and targetBitmap ~= bitmap then 
    pcall(function() targetBitmap.recycle() end) 
  end
  pcall(function() bitmap.recycle() end)
  
  return base64Str
end

local function sendGroqChat(userText, mediaData, onComplete)
  local apiKey = getApiKey()
  if apiKey == "" then
    onComplete(false, "Kunci API Groq belum diatur. Silakan masukkan kunci API terlebih dahulu.")
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

  Thread(Runnable{
    run = function()
      local jsonPayload = JSONObject()
      jsonPayload.put("model", activeModel)
      jsonPayload.put("temperature", 0.3)
      jsonPayload.put("max_tokens", 1500)

      local messagesArray = JSONArray()

      local sysInstruction = currentSysInstruction
      if sysInstruction and sysInstruction ~= "" then
        local sysObj = JSONObject()
        sysObj.put("role", "system")
        sysObj.put("content", sysInstruction)
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

      local postData = String(jsonPayload.toString()).getBytes("UTF-8")
      local success = false
      local finalResult = nil
      local errorMessage = "Waktu tunggu habis atau terjadi kesalahan koneksi."
      local maxRetries = 3
      local attempt = 0

      while attempt < maxRetries and not success do
        attempt = attempt + 1
        local conn = nil
        local reader = nil

        pcall(function()
          local endpoint = "https://api.groq.com/openai/v1/chat/completions"
          local url = URL(endpoint)
          conn = url.openConnection()
          conn.setRequestMethod("POST")
          conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
          conn.setRequestProperty("Authorization", "Bearer " .. apiKey)
          conn.setDoOutput(true)
          conn.setDoInput(true)
          conn.setConnectTimeout(15000)
          conn.setReadTimeout(30000)

          local os = conn.getOutputStream()
          os.write(postData)
          os.flush()
          os.close()

          local responseCode = conn.getResponseCode()
          if responseCode == 200 then
            reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
            local lines = {}
            local line = reader.readLine()
            while line ~= nil do
              table.insert(lines, line)
              line = reader.readLine()
            end
            reader.close()
            reader = nil

            local resObj = JSONObject(table.concat(lines, "\n"))
            local choices = resObj.optJSONArray("choices")
            if choices and choices.length() > 0 then
              local choiceMsg = choices.getJSONObject(0).optJSONObject("message")
              if choiceMsg then
                finalResult = choiceMsg.optString("content")
                success = true
              end
            end
          else
            local errStream = conn.getErrorStream()
            if errStream then
              local errReader = BufferedReader(InputStreamReader(errStream, "UTF-8"))
              local errLines = {}
              local el = errReader.readLine()
              while el ~= nil do
                table.insert(errLines, el)
                el = errReader.readLine()
              end
              errReader.close()
              pcall(function()
                local errJson = JSONObject(table.concat(errLines, "\n"))
                local errObj = errJson.optJSONObject("error")
                if errObj then
                  errorMessage = errObj.optString("message")
                end
              end)
            end
          end
        end)

        if reader then pcall(function() reader.close() end) end
        if conn then pcall(function() conn.disconnect() end) end

        if not success and attempt < maxRetries then
          pcall(function() Thread.sleep(2000) end)
        end
      end

      mainHandler.post(Runnable{
        run = function()
          if success and finalResult then
            table.insert(chatHistory, {role = "assistant", content = finalResult})
            onComplete(true, finalResult)
          else
            onComplete(false, errorMessage .. " (Gagal setelah " .. attempt .. "x percobaan)")
          end
        end
      })
    end
  }).start()
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

  local builder = AlertDialog.Builder(service)
    .setTitle("Hasil Deskripsi Layar")
    .setView(layout)
    .setPositiveButton("Menu / Setelan", function(dialog)
      dialog.dismiss()
      showMainMenu()
    end)
    .setNegativeButton("Tutup", nil)

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
        local clip = ClipData.newPlainText("Deskripsi Layar Groq", textToCopy)
        clipboard.setPrimaryClip(clip)
        service.speak("Hasil deskripsi berhasil disalin.")
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
  local input = EditText(service)
  input.setText(getApiKey())
  input.setHint("Tempel Kunci API Groq (gsk_...) di sini...")
  input.setSingleLine(true)

  local builder = AlertDialog.Builder(service)
    .setTitle("Atur Kunci API Groq")
    .setView(input)
    .setPositiveButton("Simpan", function()
      local key = tostring(input.getText()):gsub("^%s*(.-)%s*$", "%1")
      setApiKey(key)
      if key ~= "" then service.speak("Kunci API Groq berhasil disimpan.")
      else service.speak("Kunci API dikosongkan, kembali ke bawaan.") end
    end)
    .setNeutralButton("Reset Bawaan", function()
      setApiKey(defaultApiKey)
      service.speak("Kunci API dikembalikan ke setelan bawaan.")
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

startScreenDescription = function()
  if getApiKey() == "" then
    service.speak("Kunci API Groq belum diatur. Silakan masukkan kunci API terlebih dahulu.")
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

  service.speak("Memindai layar...")
  mainHandler.postDelayed(Runnable{
    run = function()
      pcall(function()
        service.takeScreenshot(Display.DEFAULT_DISPLAY, service.getMainExecutor(), TakeScreenshotCallback{
          onSuccess = function(screenshotResult)
            pcall(function()
              local hwBuffer = screenshotResult.getHardwareBuffer()
              local colorSpace = screenshotResult.getColorSpace()
              local bitmap = Bitmap.wrapHardwareBuffer(hwBuffer, colorSpace)
              if bitmap then
                local base64Screen = bitmapToBase64(bitmap, 90)
                pcall(function() hwBuffer.close() end)
                
                chatHistory = {}
                currentSysInstruction = getImageInstruction()
                
                service.speak("Menganalisis dengan Groq...")
                sendGroqChat("Deskripsikan konten utama pada layar ini secara terperinci tanpa menyebutkan bilah status atas maupun bilah navigasi bawah.", base64Screen, function(success, reply)
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
                pcall(function() hwBuffer.close() end)
                local errBmp = "Gagal memproses bitmap layar."
                chatHistory = { {role = "assistant", content = errBmp} }
                service.speak(errBmp)
                showChatDialog()
              end
            end)
          end,
          onFailure = function(errorCode)
            local errShot = "Gagal mengambil tangkapan layar. Kode: " .. tostring(errorCode)
            chatHistory = { {role = "assistant", content = errShot} }
            service.speak(errShot)
            showChatDialog()
          end
        })
      end)
    end
  }, 250)
end

local function showCustomModelDialog()
  local input = EditText(service)
  input.setText(getModelName())
  input.setHint("qwen/qwen3.8-27b")

  local builder = AlertDialog.Builder(service)
    .setTitle("Model Groq Custom")
    .setView(input)
    .setPositiveButton("Simpan", function()
      local customModel = tostring(input.getText()):gsub("^%s*(.-)%s*$", "%1")
      if customModel ~= "" then
        setModelName(customModel)
        service.speak("Model diatur ke " .. customModel)
      end
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

local function showModelSelectionDialog()
  local models = {}
  for _, m in ipairs(availableModels) do
    table.insert(models, m)
  end
  table.insert(models, "[Ketik Nama Model Lain]")
  
  local currentModel = getModelName()
  local selectedIndex = 0
  for i, model in ipairs(models) do
    if model == currentModel then
      selectedIndex = i - 1
      break
    end
  end

  local builder = AlertDialog.Builder(service)
    .setTitle("Pilih Model Groq Vision")
    .setSingleChoiceItems(models, selectedIndex, function(dialog, which)
      local chosenModel = models[which + 1]
      dialog.dismiss()
      if chosenModel == "[Ketik Nama Model Lain]" then
        showCustomModelDialog()
      else
        setModelName(chosenModel)
        service.speak("Model diubah ke " .. chosenModel)
      end
    end)
    .setNegativeButton("Tutup", nil)

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
      service.speak("Instruksi layar berhasil disimpan.")
    end)
    .setNeutralButton("Reset Default", function()
      setImageInstruction(defaultImageInstruction)
      service.speak("Instruksi layar dikembalikan ke default.")
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

local function showModeSelectionDialog()
  local modeOptions = {
    "Mode Langsung - Deskripsikan Layar",
    "Mode Normal - Buka Menu Utama"
  }
  
  local currentMode = getAppMode()
  local selectedIndex = 0
  if currentMode == "normal" then 
    selectedIndex = 1 
  end

  local builder = AlertDialog.Builder(service)
    .setTitle("Pilih Mode Peluncuran")
    .setSingleChoiceItems(modeOptions, selectedIndex, function(dialog, which)
      dialog.dismiss()
      if which == 0 then
        setAppMode("direct_image")
        service.speak("Mode Langsung diaktifkan.")
      else
        setAppMode("normal")
        service.speak("Mode Normal diaktifkan.")
      end
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(builder)
end

-- Menu Utama
showMainMenu = function()
  local currentKeyStatus = (getApiKey() ~= "") and "Terpasang" or "Belum Diatur"
  
  local menuItems = {
    "1. Deskripsikan Layar",
    "2. Atur Kunci API Groq (" .. currentKeyStatus .. ")",
    "3. Pengaturan Mode Peluncuran",
    "4. Model Vision Groq (Aktif: " .. getModelName() .. ")",
    "5. Atur Instruksi Deskripsi Layar",
    "6. Periksa Pembaruan Script (v" .. CURRENT_VERSION .. ")"
  }

  local builder = AlertDialog.Builder(service)
    .setTitle("Deskripsi Layar Groq AI (v" .. CURRENT_VERSION .. ")")
    .setItems(menuItems, function(dialog, which)
      dialog.dismiss()
      if which == 0 then startScreenDescription()
      elseif which == 1 then showApiKeyDialog()
      elseif which == 2 then showModeSelectionDialog()
      elseif which == 3 then showModelSelectionDialog()
      elseif which == 4 then showImageInstructionDialog()
      elseif which == 5 then checkAppUpdate(true)
      end
    end)
    .setNegativeButton("Tutup", nil)

  displayOverlayDialog(builder)
end

-- Eksekusi awal
local startMode = getAppMode()
if startMode == "direct_image" or startMode == "direct" then
  startScreenDescription()
else
  showMainMenu()
  -- Cek pembaruan otomatis di latar belakang saat membuka menu
  mainHandler.postDelayed(Runnable{
    run = function()
      checkAppUpdate(false)
    end
  }, 1000)
end
