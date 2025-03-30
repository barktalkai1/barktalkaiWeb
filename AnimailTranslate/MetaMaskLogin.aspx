<%@ Page Language="C#" AutoEventWireup="true" CodeFile="MetaMaskLogin.aspx.cs" Inherits="MetaMaskLogin" %>

<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MetaMask 登录</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ethers/5.7.2/ethers.umd.min.js"></script>
</head>
<body>
    <button id="connectWallet">连接 MetaMask</button>
    <p>钱包地址: <span id="walletAddress">未连接</span></p>
    <button id="signMessage" style="display: none;">签名并登录</button>

    <script>
        $(document).ready(function () {
            let userAddress = "";

            if (typeof window.ethereum !== 'undefined') {
                console.log("✅ MetaMask 已安装");

                $("#connectWallet").click(async function () {
                    try {
                        const provider = new ethers.providers.Web3Provider(window.ethereum);

                        // 请求用户授权访问账户
                        const accounts = await provider.send("eth_requestAccounts", []);

                        if (accounts.length === 0) {
                            alert("未获取到 MetaMask 账户，请检查钱包是否解锁！");
                            return;
                        }

                        userAddress = accounts[0]; // 获取第一个账户地址
                        console.log("✅ 获取到钱包地址:", userAddress);

                        // 显示地址
                        $("#walletAddress").text(userAddress);
                        $("#signMessage").show();

                    } catch (error) {
                        console.error("❌ 连接失败:", error);
                        alert("连接钱包失败，请重试！");
                    }
                });

                $("#signMessage").click(async function () {
                    try {
                        const provider = new ethers.providers.Web3Provider(window.ethereum);
                        const signer = provider.getSigner();
                        const message = "请使用 MetaMask 签署此消息以验证您的身份";
                        const signature = await signer.signMessage(message);

                        console.log("✍️ 签名:", signature);
                       
                        $.ajax({
                            url: '/ajax/ajax.ashx',
                            type: 'POST',
                            data: {
                                act: "VerifySignature",
                                walletAddress: userAddress,
                                signature: signature,
                                message: message
                            }, 
                            dataType: 'json',
                            success: function (response) {
                                console.log("✅ 服务器返回:", response);
                                alert(response.message);
                            },
                            error: function (xhr, status, error) {
                                console.error("❌ 请求失败:", xhr.responseText);
                                alert("服务器错误，请检查 Console 日志！");
                            }
                        });

                    } catch (error) {
                        console.error("❌ 签名失败:", error);
                        alert("签名失败，请重试！");
                    }
                });

            } else {
                alert("❌ 请安装 MetaMask 扩展！");
            }
        });
    </script>
</body>
</html>