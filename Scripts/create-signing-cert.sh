#!/bin/bash
# 创建本机自签名代码签名证书 "CopyListDev"（有效期 10 年）。
# 用途：让 CopyList 每次重新构建/更新后签名身份保持不变，
#       系统辅助功能（Accessibility）等 TCC 授权因此跨版本保留，无需重复授权。
set -e

CERT_NAME="CopyListDev"
DAYS=3650
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "🔑 创建自签名代码签名证书：$CERT_NAME（有效期 $DAYS 天）..."

# 已存在同名有效身份时直接退出（幂等）
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
    echo "✅ 证书 \"$CERT_NAME\" 已存在，跳过创建。"
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    exit 0
fi

# 生成带 codeSigning 扩展用途的证书（兼容 macOS 自带 LibreSSL：使用配置文件而非 -addext）
cat > "$WORKDIR/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions    = v3_req
prompt             = no
[dn]
CN = $CERT_NAME
[v3_req]
keyUsage            = critical, digitalSignature
extendedKeyUsage    = codeSigning
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:3072 -nodes \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -days "$DAYS" -config "$WORKDIR/openssl.cnf" 2>/dev/null

# 打包成 p12 导入登录钥匙串，并预先授权 /usr/bin/codesign 使用该私钥
# 注意：macOS 自带 security 工具不认 OpenSSL 3 默认的 PBES2 加密，必须用传统 3DES/SHA1 算法导出
openssl pkcs12 -export -out "$WORKDIR/cert.p12" \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
    -passout pass:copylist-tmp 2>/dev/null

echo "📥 导入登录钥匙串（如弹出钥匙串访问确认框请允许）..."
security import "$WORKDIR/cert.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P copylist-tmp -T /usr/bin/codesign

echo "🛡️  将证书标记为可信的代码签名证书（用户域，无需管理员密码）..."
if ! security add-trusted-cert -r trustRoot -p codeSign "$WORKDIR/cert.pem"; then
    echo "⚠️  自动信任失败。请手动操作："
    echo "    打开「钥匙串访问」→ 登录 → 证书 \"$CERT_NAME\" → 显示简介 → 信任 →"
    echo "    「代码签名」设为「始终信任」。"
    exit 1
fi

echo ""
echo "✅ 证书创建完成。当前可用的代码签名身份："
security find-identity -v -p codesigning
echo ""
echo "后续构建将使用该证书签名，更新版本不再丢失辅助功能授权。"
echo "如需在其他 Mac 上签名，请从「钥匙串访问」导出 \"$CERT_NAME\"（含私钥的 .p12）。"
