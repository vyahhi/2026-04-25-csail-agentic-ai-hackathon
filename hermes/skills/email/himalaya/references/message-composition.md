# Himalaya message composition

Preferred non-interactive pattern:

```bash
cat << 'EOF' | himalaya template send
From: you@example.com
To: recipient@example.com
Subject: Subject here

Body text here.
EOF
```

Reply template flow:

```bash
himalaya template reply 42 | sed 's/^$/\nYour reply text here\n/' | himalaya template send
```

Forward template flow:

```bash
himalaya template forward 42 | sed 's/^To:.*/To: newrecipient@example.com/' | himalaya template send
```

Piped input is generally more reliable for automation than interactive editor mode.
