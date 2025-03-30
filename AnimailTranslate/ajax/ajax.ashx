<%@ WebHandler Language="C#" Class="AjaxHandler" %>

using System;
using System.IO;
using System.Web;
using System.Web.Script.Serialization;
using CSCore;
using CSCore.Codecs.WAV;
using CSCore.DSP;
using System.Numerics;
using System.Collections.Generic;
using System.Linq;
using Nethereum.Signer;
using MathNet.Numerics.IntegralTransforms;
using System.Diagnostics;
using System.Net;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
using System.Threading.Tasks;
using System.Data;
using System.Data.SqlClient;
using System.Collections.Specialized;


public class AjaxHandler : IHttpHandler
{
    public void ProcessRequest(HttpContext context)
    {
        context.Response.ContentType = "application/json";
        JavaScriptSerializer js = new JavaScriptSerializer();
        string result = "";
        string action = context.Request.Form["act"];
        //2.后台接收Action后进行处理
        if (action != "")
        {
            //2.后台接收Action后进行处理
            switch (action)
            {

                case "AnalysisRecord": //录音分析
                    result = AnalysisRecord(context);
                    break;
                case "AnalysisVideo": //视频分析
                    result = AnalysisVideo(context);
                    break;

                case "VerifySignature": //钱包登录-签名
                    result = VerifySignature(context);
                    break;
                case "GetUserPlan": // 新增查询套餐功能
                    result = GetUserPlan(context);
                    break;
                case "UpdateUserPlan": // 更新用户套餐
                    result = UpdateUserPlan(context);
                    break;
                case "CheckRemainingTime": // 检查用户剩余时间
                    result = CheckRemainingTime(context);
                    break;
                case "DeductTime": // 每分钟扣费
                    result = DeductTime(context);
                    break;

            }
            //将json返回前端
            context.Response.Write(result);
        }
        else
        {
            context.Response.Write(js.Serialize(new { message = "❌ 缺少参数 act" }));

        }
    }

    //调用MMAction2的人工智能模型进行狗狗行为识别
    public string AnalysisVideo(HttpContext context)
    {
        JavaScriptSerializer js = new JavaScriptSerializer();
        int fileCount = context.Request.Files.Count;
        System.Diagnostics.Debug.WriteLine("上传视频数量: " + fileCount);

        if (fileCount > 0)
        {
            HttpPostedFile file = context.Request.Files["video"];
            if (file != null && file.ContentLength > 0)
            {
                string uploadFolder = context.Server.MapPath("~/Uploads/");
                if (!Directory.Exists(uploadFolder))
                {
                    Directory.CreateDirectory(uploadFolder);
                }

                string mp4FileName = Guid.NewGuid().ToString() + ".mp4";
                string mp4FilePath = Path.Combine(uploadFolder, mp4FileName);
                file.SaveAs(mp4FilePath);

                try
                {
                    // === 1️⃣ 调用 YOLO 接口检测是否有狗 ===
                    byte[] yoloResponse = UploadFileToUrl("http://47.239.65.125:1786/detect/", mp4FilePath, "video");
                    string yoloJson = Encoding.UTF8.GetString(yoloResponse);
                    var yoloResult = js.Deserialize<Dictionary<string, object>>(yoloJson);

                    var detectedObjectsRaw = (System.Collections.ArrayList)yoloResult["detected_objects"];
                    bool foundDog = false;
                    double dogConfidence = 0.0;

                    foreach (var obj in detectedObjectsRaw)
                    {
                        var dict = (Dictionary<string, object>)obj;
                        if (dict["class"].ToString() == "dog")
                        {
                            dogConfidence = Convert.ToDouble(dict["confidence"]);
                            //狗狗置信度需要0.8以上
                            if (dogConfidence >= 0.7)
                            {
                                foundDog = true;
                                break;
                            }
                        }
                    }

                    // === 2️⃣ 如果没有狗，直接返回提示 ===
                    if (!foundDog)
                    {
                        string NoDogSiliconflowTip = CallSiliconflowAPIVideo("NoDog");
                        NoDogSiliconflowTip = ExtractContent(NoDogSiliconflowTip);
                        return js.Serialize(new
                        {
                            status = "success",
                            //DogMessage = "画面中没有检测到狗狗（置信度不足）",
                            DogMessage =NoDogSiliconflowTip,
                            raw = yoloResult
                        });
                    }

                    // === 3️⃣ 调用行为识别接口 ===
                    byte[] predictResponse = UploadFileToUrl("http://47.239.65.125:1785/predict/", mp4FilePath, "video");
                    string responseText = Encoding.UTF8.GetString(predictResponse);

                    var rawResult = js.Deserialize<Dictionary<string, object>>(responseText);
                    var prediction = (Dictionary<string, object>)rawResult["prediction"];

                    string bestEmotion = "";
                    double maxScore = -1;

                    foreach (var item in prediction)
                    {
                        double score = Convert.ToDouble(item.Value);
                        if (score > maxScore)
                        {
                            maxScore = score;
                            bestEmotion = item.Key;
                        }
                    }

                    string  message = $"狗狗当前情绪为『{bestEmotion}』，置信度为 {(maxScore * 100).ToString("F2")}%";
                    string SiliconflowWords = CallSiliconflowAPIVideo(bestEmotion);
                    string DogMessage = message + "</br>" + ExtractContent(SiliconflowWords);

                    return js.Serialize(new
                    {
                        status = "success",
                        DogMessage = DogMessage,
                        raw = rawResult
                    });
                }
                catch (Exception ex)
                {
                    return js.Serialize(new { status = "error", message = "视频分析请求失败", error = ex.Message });
                }
            }
            else
            {
                return js.Serialize(new { status = "error", message = "上传视频为空" });
            }
        }
        else
        {
            return js.Serialize(new { status = "error", message = "没有检测到视频文件" });
        }
    }


    public byte[] UploadFileToUrl(string url, string filePath, string fieldName)
    {
        string boundary = "----WebKitFormBoundary" + DateTime.Now.Ticks.ToString("x");
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
        request.Method = "POST";
        request.ContentType = "multipart/form-data; boundary=" + boundary;

        byte[] fileData = File.ReadAllBytes(filePath);
        string header = $"--{boundary}\r\nContent-Disposition: form-data; name=\"{fieldName}\"; filename=\"{Path.GetFileName(filePath)}\"\r\nContent-Type: video/mp4\r\n\r\n";
        string footer = $"\r\n--{boundary}--\r\n";

        byte[] headerBytes = Encoding.UTF8.GetBytes(header);
        byte[] footerBytes = Encoding.UTF8.GetBytes(footer);

        using (Stream requestStream = request.GetRequestStream())
        {
            requestStream.Write(headerBytes, 0, headerBytes.Length);
            requestStream.Write(fileData, 0, fileData.Length);
            requestStream.Write(footerBytes, 0, footerBytes.Length);
        }

        using (WebResponse response = request.GetResponse())
        using (MemoryStream ms = new MemoryStream())
        {
            response.GetResponseStream().CopyTo(ms);
            return ms.ToArray();
        }
    }




    // 每分钟扣除 1 分钟的剩余时间
    public string DeductTime(HttpContext context)
    {
        JavaScriptSerializer js = new JavaScriptSerializer();
        string walletAddress = context.Request.Form["wallet"];

        if (string.IsNullOrEmpty(walletAddress))
        {
            return js.Serialize(new { success = false, message = "❌ Wallet address is missing." });
        }

        int remainingTime = 0; // 提前声明 remainingTime 变量

        try
        {
            string connectionString = "Server=47.239.65.125;Database=BPMS_AnimailTranslate;User Id=sa;Password=GOUFANYI;";
            using (SqlConnection conn = new SqlConnection(connectionString))
            {
                conn.Open();
                string query = "SELECT RemainingTime FROM BPMS_ATU WHERE WalletAddress = @wallet";
                SqlCommand cmd = new SqlCommand(query, conn);
                cmd.Parameters.AddWithValue("@wallet", walletAddress);
                object remainingTimeObj = cmd.ExecuteScalar();

                if (remainingTimeObj == null)
                {
                    return js.Serialize(new { success = false, message = "❌ No active plan found." });
                }

                remainingTime = Convert.ToInt32(remainingTimeObj); // 赋值到作用域外的变量
                if (remainingTime <= 0)
                {
                    return js.Serialize(new { success = false, remainingTime = 0, message = "⏳ No time left." });
                }

                // 扣除 1 分钟
                remainingTime = Math.Max(remainingTime - 1, 0);
                string updateQuery = "UPDATE BPMS_ATU SET RemainingTime = @newTime, Last_UpdateTime = GETDATE() WHERE WalletAddress = @wallet";
                SqlCommand updateCmd = new SqlCommand(updateQuery, conn);
                updateCmd.Parameters.AddWithValue("@newTime", remainingTime);
                updateCmd.Parameters.AddWithValue("@wallet", walletAddress);
                updateCmd.ExecuteNonQuery();
            }

            return js.Serialize(new { success = true, remainingTime = remainingTime, message = "✅ Time deducted successfully." });
        }
        catch (Exception ex)
        {
            return js.Serialize(new { success = false, remainingTime = remainingTime, message = "❌ Database error: " + ex.Message });
        }
    }



    // 检查用户剩余时间
    private string CheckRemainingTime(HttpContext context)
    {
        JavaScriptSerializer js = new JavaScriptSerializer();
        string walletAddress = context.Request.Form["wallet"];

        if (string.IsNullOrEmpty(walletAddress))
        {
            return js.Serialize(new { success = false, message = "❌ 钱包地址不能为空" });
        }

        string connectionString = "Server=47.239.65.125;Database=BPMS_AnimailTranslate;User Id=sa;Password=GOUFANYI;";
        using (SqlConnection conn = new SqlConnection(connectionString))
        {
            conn.Open();
            string query = "SELECT RemainingTime FROM BPMS_ATU WHERE WalletAddress = @WalletAddress";
            using (SqlCommand cmd = new SqlCommand(query, conn))
            {
                cmd.Parameters.AddWithValue("@WalletAddress", walletAddress);
                object result = cmd.ExecuteScalar();

                if (result != null)
                {
                    int remainingTime = Convert.ToInt32(result);
                    return js.Serialize(new { success = true, remainingTime = remainingTime });
                }
                else
                {
                    return js.Serialize(new { success = false, message = "❌ 未找到该钱包的套餐信息" });
                }
            }
        }
    }


    // 处理用户套餐更新
    public string UpdateUserPlan(HttpContext context)
    {
        JavaScriptSerializer js = new JavaScriptSerializer();
        string wallet = context.Request.Form["wallet"];
        int additionalMinutes;

        if (string.IsNullOrEmpty(wallet) || !int.TryParse(context.Request.Form["minutes"], out additionalMinutes))
        {
            return js.Serialize(new { success = false, message = "❌ 参数错误" });
        }

        string connectionString = "Server=47.239.65.125;Database=BPMS_AnimailTranslate;User Id=sa;Password=GOUFANYI;";
        int remainingTime = 0;

        using (SqlConnection conn = new SqlConnection(connectionString))
        {
            conn.Open();
            string queryCheck = "SELECT RemainingTime FROM BPMS_ATU WHERE WalletAddress = @WalletAddress";
            SqlCommand cmdCheck = new SqlCommand(queryCheck, conn);
            cmdCheck.Parameters.AddWithValue("@WalletAddress", wallet);

            object result = cmdCheck.ExecuteScalar();

            if (result != null)  // 账户已存在，更新时间
            {
                remainingTime = Convert.ToInt32(result) + additionalMinutes;
                string queryUpdate = "UPDATE BPMS_ATU SET RemainingTime = @RemainingTime, last_UpdateTime = GETDATE() WHERE WalletAddress = @WalletAddress";
                SqlCommand cmdUpdate = new SqlCommand(queryUpdate, conn);
                cmdUpdate.Parameters.AddWithValue("@RemainingTime", remainingTime);
                cmdUpdate.Parameters.AddWithValue("@WalletAddress", wallet);
                cmdUpdate.ExecuteNonQuery();
            }
            else  // 账户不存在，新增记录
            {
                remainingTime = additionalMinutes;
                string queryInsert = "INSERT INTO BPMS_ATU (WalletAddress, RemainingTime, add_time) VALUES (@WalletAddress, @RemainingTime, GETDATE())";
                SqlCommand cmdInsert = new SqlCommand(queryInsert, conn);
                cmdInsert.Parameters.AddWithValue("@WalletAddress", wallet);
                cmdInsert.Parameters.AddWithValue("@RemainingTime", remainingTime);
                cmdInsert.ExecuteNonQuery();
            }
        }

        return js.Serialize(new { success = true, remainingTime = remainingTime });
    }


    // 查询用户套餐信息
    private string GetUserPlan(HttpContext context)
    {
        JavaScriptSerializer js = new JavaScriptSerializer();
        string wallet = context.Request.Form["wallet"];

        if (string.IsNullOrEmpty(wallet))
        {
            return js.Serialize(new { success = false, message = "❌ Wallet address is required" });
        }

        // 直接写入数据库连接信息
        string connectionString = "Server=47.239.65.125;Database=BPMS_AnimailTranslate;User Id=sa;Password=GOUFANYI;";

        try
        {
            using (SqlConnection conn = new SqlConnection(connectionString))
            {
                conn.Open();
                string query = "SELECT RemainingTime FROM BPMS_ATU WHERE walletAddress = @wallet";

                using (SqlCommand cmd = new SqlCommand(query, conn))
                {
                    cmd.Parameters.AddWithValue("@wallet", wallet);

                    object result = cmd.ExecuteScalar();

                    if (result != null)
                    {
                        int remainingTime = Convert.ToInt32(result);

                        var response = new
                        {
                            success = true,
                            wallet = wallet,
                            remainingTime = remainingTime
                        };

                        return js.Serialize(response);
                    }
                    else
                    {
                        return js.Serialize(new { success = false, message = "⚠️ No plan found for this wallet" });
                    }
                }
            }
        }
        catch (Exception ex)
        {
            return js.Serialize(new { success = false, message = "❌ Database error: " + ex.Message });
        }
    }


    // 录音分析：保存上传的文件，读取文件并计算平均音高
    public string AnalysisRecord(HttpContext context)
    {

        JavaScriptSerializer js = new JavaScriptSerializer();
        int fileCount = context.Request.Files.Count;
        System.Diagnostics.Debug.WriteLine("上传文件数量: " + fileCount);

        if (fileCount > 0)
        {
            HttpPostedFile file = context.Request.Files["audio"];
            if (file != null && file.ContentLength > 0)
            {
                // 保存上传的 WebM 文件
                string uploadFolder = context.Server.MapPath("~/Uploads/");
                if (!Directory.Exists(uploadFolder))
                {
                    Directory.CreateDirectory(uploadFolder);
                }

                // 使用 GUID 生成唯一文件名，保留 .webm 扩展名
                string webmFileName = Guid.NewGuid().ToString() + ".webm";
                string webmFilePath = Path.Combine(uploadFolder, webmFileName);
                file.SaveAs(webmFilePath);

                // 定义转换后的 WAV 文件名和路径
                string wavFileName = Path.GetFileNameWithoutExtension(webmFileName) + ".wav";
                string wavFilePath = Path.Combine(uploadFolder, wavFileName);

                // 调用 FFmpeg 进行转换
                bool conversionSuccess = ConvertWebmToWav(webmFilePath, wavFilePath);
                if (!conversionSuccess)
                {
                    return js.Serialize(new { status = "error", message = "转换失败" });

                }

                // 调用方法计算音频文件的平均音高（Hz）
                float avgHz = CalculateAveragePitch(wavFilePath);
                //调用柯基情绪算法
                float emotionScore = CorgiEmotionAnalysis(avgHz);
                //调用SiliconflowWords返回情绪分语句
                string SiliconflowWords = CallSiliconflowAPI(emotionScore);
                //提取返回信息内容
                string DogMessage = ExtractContent(SiliconflowWords);
                // 返回成功提示，同时返回文件名和平均音高值
                return js.Serialize(new { status = "success", message = "文件上传成功！", fileName = wavFilePath, hzvalue = avgHz, emotionScore = emotionScore, DogMessage = DogMessage });
            }
            else
            {
                return js.Serialize(new { status = "error", message = "上传文件为空" });
            }
        }
        else
        {
            return js.Serialize(new { status = "error", message = "没有检测到文件！" });
        }


    }

    //提取返回api的内容
    public static string ExtractContent(string jsonString)
    {
        try
        {
            // 解析 JSON 字符串
            JObject jsonObject = JObject.Parse(jsonString);

            // 提取 content 字段
            string content = jsonObject["choices"]?[0]?["message"]?["content"]?.ToString();

            // 如果 content 为空，返回默认提示
            return content ?? "未找到 AI 返回的内容";
        }
        catch (Exception ex)
        {
            return $"解析错误: {ex.Message}";
        }
    }

    //调用SiliconflowAPI
    private string CallSiliconflowAPI(float emotionScore)
    {
        // API地址
        string apiUrl = "https://api.siliconflow.cn/v1/chat/completions";
        string apiKey = "sk-tyfjuaxevazwbihodhbfozqpsoxmxkwcrrjabmnpxerbvtzk"; // ⚠️ 建议从 Web.config 读取

        // 构建请求体
        var requestBody = new
        {
            //模型
            model = "Qwen/Qwen2.5-72B-Instruct",
            messages = new[]
            {
                new
                {
                    role = "user",
                    content = $"以柯基犬的口吻表达柯基想说的话，我会提供给你情绪分，情绪分从-100分到100分，不需要加入动作，不要加入表情描述，生成字数在15字左右，输出的时候以主人称呼我，当前情绪分为{emotionScore}。"
                }
            },
            temperature = 0.7
        };

        // 将请求体转换为JSON
        string jsonRequestBody = JsonConvert.SerializeObject(requestBody);

        string result = PostUrl(apiUrl, jsonRequestBody, apiKey);

        return result;
    }

    //调用SiliconflowAPI
    private string CallSiliconflowAPIVideo(string emotionScore)
    {
        // API地址
        string apiUrl = "https://api.siliconflow.cn/v1/chat/completions";
        string apiKey = "sk-tyfjuaxevazwbihodhbfozqpsoxmxkwcrrjabmnpxerbvtzk"; // ⚠️ 建议从 Web.config 读取

        // 构建请求体
        var requestBody = new
        {
            //模型
            model = "Qwen/Qwen2.5-72B-Instruct",
            messages = new[]
            {
              new
              {
                  role = "user",
                  content = $"以狗狗的口吻表达狗狗想说的话，我会提供给你情绪，情绪有以下几种，NoDog代表画面中没有识别到狗狗，你要输出卡哇伊的没有检测到狗狗的语句表达，DogHunger代表狗狗饿了，DogWantPee代表狗狗要尿尿，DogWantPlay代表狗狗要玩，你的回复中不需要加入动作，不要加入表情描述，生成字数在15字左右，输出的时候以主人称呼我，当前情绪为{emotionScore}。"
              }
          },
            temperature = 0.7
        };

        // 将请求体转换为JSON
        string jsonRequestBody = JsonConvert.SerializeObject(requestBody);

        string result = PostUrl(apiUrl, jsonRequestBody, apiKey);

        return result;
    }

    //发送POST请求
    private static string PostUrl(string url, string postData, string apiKey)
    {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Ssl3
                                       | SecurityProtocolType.Tls
                                       | (SecurityProtocolType)0x300 //Tls11
                                       | (SecurityProtocolType)0xC00; //Tls12

        HttpWebRequest request = null;
        if (url.StartsWith("https", StringComparison.OrdinalIgnoreCase))
        {
            request = WebRequest.Create(url) as HttpWebRequest;
            ServicePointManager.ServerCertificateValidationCallback = new RemoteCertificateValidationCallback(CheckValidationResult);
            request.ProtocolVersion = HttpVersion.Version11;
            // 这里设置了协议类型。
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;// SecurityProtocolType.Tls1.2; 
            request.KeepAlive = false;
            ServicePointManager.CheckCertificateRevocationList = true;
            ServicePointManager.DefaultConnectionLimit = 100;
            ServicePointManager.Expect100Continue = false;
        }
        else
        {
            request = (HttpWebRequest)WebRequest.Create(url);
        }

        request.Method = "POST";
        request.ContentType = "application/json";
        request.Headers.Add("Authorization", $"Bearer {apiKey}");

        byte[] data = Encoding.UTF8.GetBytes(postData);
        Stream newStream = request.GetRequestStream();
        newStream.Write(data, 0, data.Length);
        newStream.Close();

        //获取网页响应结果
        HttpWebResponse response = (HttpWebResponse)request.GetResponse();
        Stream stream = response.GetResponseStream();
        //client.Headers.Add("Content-Type", "application/x-www-form-urlencoded");
        string result = string.Empty;
        using (StreamReader sr = new StreamReader(stream))
        {
            result = sr.ReadToEnd();
        }

        return result;
    }

    private static bool CheckValidationResult(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors errors)
    {
        return true; //总是接受  
    }



    //    //连接chatgpt的api返回
    //    private string CallChatGptAPI(float emotionScore) {
    //    // API地址
    //    string apiUrl = "https://api.openai.com/v1/chat/completions";
    //    string apiKey = "YOUR_API_KEY"; // 替换为你的API密钥

    //    // 构建请求体
    //    var requestBody = new {
    //        model = "gpt-4",
    //        messages = new[] {
    //            new {
    //                role = "user",
    //                content = $"以柯基犬的口吻表达情绪，当前情绪分为{emotionScore}。"
    //            }
    //        },
    //        temperature = 0.7
    //    };

    //    // 将请求体转换为JSON
    //    string jsonRequestBody = Newtonsoft.Json.JsonConvert.SerializeObject(requestBody);

    //    // 创建HTTP请求
    //    HttpWebRequest request = (HttpWebRequest)WebRequest.Create(apiUrl);
    //    request.Method = "POST";
    //    request.ContentType = "application/json";
    //    request.Headers.Add("Authorization", $"Bearer {apiKey}");

    //    // 写入请求体
    //    using (var streamWriter = new StreamWriter(request.GetRequestStream())) {
    //        streamWriter.Write(jsonRequestBody);
    //        streamWriter.Flush();
    //    }

    //    // 获取响应
    //    try {
    //        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
    //        using (Stream responseStream = response.GetResponseStream())
    //        using (StreamReader reader = new StreamReader(responseStream)) {
    //            string jsonResponse = reader.ReadToEnd();
    //            return jsonResponse;
    //        }
    //    } catch (WebException ex) {
    //        // 处理错误
    //        using (Stream responseStream = ex.Response.GetResponseStream())
    //        using (StreamReader reader = new StreamReader(responseStream)) {
    //            string errorResponse = reader.ReadToEnd();
    //            return $"{{\"error\": \"API调用失败\", \"details\": \"{errorResponse}\"}}";
    //        }
    //    }
    //}



    //柯基叫声情绪表
    //{ "frequency": 50, "score": -80 },
    //{ "frequency": 60, "score": -60 },
    //{ "frequency": 70, "score": -40 },
    //{ "frequency": 80, "score": -20 },
    //{ "frequency": 90, "score": 0 },
    //{ "frequency": 100, "score": 20 },
    //{ "frequency": 110, "score": 40 },
    //{ "frequency": 120, "score": 60 },
    //{ "frequency": 130, "score": 80 },
    //{ "frequency": 140, "score": 100 }
    public float CorgiEmotionAnalysis(float InputHz)
    {
        float score = 0;

        if (InputHz < 50)
        {
            score = -100;
        }
        else if (InputHz > 140)
        {
            score = 100;
        }
        else
        {
            // 50 Hz 映射为 -80 分，140 Hz 映射为 100 分，中间采用线性插值计算
            score = ((InputHz - 50) / 10f) * 20 - 80;
        }

        return score;
    }


    /// <summary>
    /// 调用 FFmpeg 将 WebM 文件转换为 WAV 文件
    /// </summary>
    /// <param name="webmPath">输入 WebM 文件的完整路径</param>
    /// <param name="wavPath">输出 WAV 文件的完整路径</param>
    /// <returns>转换成功返回 true，否则 false</returns>
    private bool ConvertWebmToWav(string webmPath, string wavPath)
    {
        try
        {
            // 设置 FFmpeg.exe 的路径，如果 FFmpeg 已加入 PATH，此处只写文件名即可
            string ffmpegPath = HttpContext.Current.Server.MapPath("~/tool/ffmpeg.exe");
            // 构建转换参数：-i 输入文件，-vn 表示不处理视频流，
            // -acodec pcm_s16le 表示使用 PCM 16位编码，-ar 44100 表示采样率 44100 Hz，-ac 2 表示双声道
            string arguments = $"-i \"{webmPath}\" -vn -acodec pcm_s16le -ar 44100 -ac 2 \"{wavPath}\"";

            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = ffmpegPath,
                Arguments = arguments,
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            using (Process process = Process.Start(startInfo))
            {
                // 读取标准错误输出（FFmpeg 的日志通常输出在这里）
                string errorOutput = process.StandardError.ReadToEnd();
                process.WaitForExit();

                // 可选：检查返回码，FFmpeg 返回码为 0 表示成功
                if (process.ExitCode != 0)
                {
                    // 可以记录 errorOutput 进行调试
                    System.Diagnostics.Debug.WriteLine("FFmpeg 转换错误：" + errorOutput);
                    return false;
                }
            }
            return true;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("调用 FFmpeg 异常：" + ex.Message);
            return false;
        }
    }


    //钱包登录-签名
    public string VerifySignature(HttpContext context)
    {
        JavaScriptSerializer js = new JavaScriptSerializer();
        // **获取数据**
        string walletAddress = context.Request.Form["walletAddress"];
        string signature = context.Request.Form["signature"];
        string message = context.Request.Form["message"];

        if (string.IsNullOrEmpty(walletAddress) || string.IsNullOrEmpty(signature) || string.IsNullOrEmpty(message))
        {
            return js.Serialize(new { message = "❌ 请求参数无效" });

        }

        var signer = new EthereumMessageSigner();
        var addressRecovered = signer.EncodeUTF8AndEcRecover(message, signature);

        if (string.IsNullOrEmpty(addressRecovered))
        {
            return js.Serialize(new { message = "❌ 签名解析失败" });

        }

        if (addressRecovered.ToLower() == walletAddress.ToLower())
        {
            return js.Serialize(new { message = "✅ 签名验证成功", walletAddress = walletAddress });
        }
        else
        {

            return js.Serialize(js.Serialize(new { message = "❌ 签名无效" }));
        }

    }

    /// <summary>
    /// 计算 WAV 文件的平均音高（Hz）
    /// 使用 CSCore 读取 WAV 文件，然后对每一段进行 FFT 分析，找到该段的主频，最后取所有帧主频的平均值作为近似“平均音高”
    /// </summary>
    /// <param name="filePath">WAV 文件的物理路径</param>
    /// <returns>平均音高（Hz）</returns>
    private float CalculateAveragePitch(string filePath)
    {
        List<double> pitchList = new List<double>();
        int fftSize = 4096; // FFT 的采样点数（可根据需要调整）
        try
        {
            using (var waveSource = new WaveFileReader(filePath))
            {
                // 转换为采样数据流
                var sampleProvider = waveSource.ToSampleSource();
                int sampleRate = waveSource.WaveFormat.SampleRate;
                float[] buffer = new float[fftSize];
                int read;
                while ((read = sampleProvider.Read(buffer, 0, buffer.Length)) > 0)
                {
                    // 构造 FFT 输入的 Complex 数组，不足部分补零
                    Complex[] complexSamples = new Complex[fftSize];
                    for (int i = 0; i < fftSize; i++)
                    {
                        double sample = (i < read) ? buffer[i] : 0;
                        complexSamples[i] = new Complex(sample, 0);
                    }

                    // 使用 MathNet.Numerics 进行 FFT 变换
                    Fourier.Forward(complexSamples, FourierOptions.Matlab);

                    // 在前半部分频谱中找到幅值最大的频率索引
                    double maxMag = 0;
                    int maxIndex = 0;
                    for (int i = 0; i < fftSize / 2; i++)
                    {
                        double mag = complexSamples[i].Magnitude;
                        if (mag > maxMag)
                        {
                            maxMag = mag;
                            maxIndex = i;
                        }
                    }

                    // 计算该帧对应的频率：频率 = 采样率 * 索引 / FFT 大小
                    double freq = sampleRate * maxIndex / (double)fftSize;
                    pitchList.Add(freq);
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("计算平均音高时发生异常: " + ex.Message);
        }
        // 返回所有帧主频的平均值；如果没有数据则返回 0
        return pitchList.Count > 0 ? (float)pitchList.Average() : 0;
    }




    public bool IsReusable
    {
        get { return false; }
    }
}
