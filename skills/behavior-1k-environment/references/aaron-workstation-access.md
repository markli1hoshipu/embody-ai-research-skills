# Aaron Workstation Access

The working BEHAVIOR-1K source with RTX 5080 support lives on aaron-workstation.

## Connection Details

- **Host**: 192.168.50.10 (aaron-workstation)
- **User**: guest
- **Key**: ~/.ssh/id_ed25519_mark
- **Passphrase**: 050120
- **Auth method**: publickey with passphrase (no password auth)

## SSH Command

The key has a passphrase, so use SSH_ASKPASS:

```bash
cat > /tmp/sshpass.sh << 'EOF'
#!/bin/bash
echo "050120"
EOF
chmod +x /tmp/sshpass.sh

SSH_ASKPASS=/tmp/sshpass.sh SSH_ASKPASS_REQUIRE=force \
  ssh -o ConnectTimeout=10 -i ~/.ssh/id_ed25519_mark guest@192.168.50.10 "command"
```

## Key Paths on aaron-workstation

- **BEHAVIOR-1K source**: `/home/aaron/BEHAVIOR-1K/`
- **Working conda env**: `/home/aaron/miniforge3/envs/behavior_5_0/`
- **Pip freeze**: Can be exported with `/home/aaron/miniforge3/envs/behavior_5_0/bin/pip freeze`
- **GPUs**: 2x RTX 5080

## Rsync Command (excluding heavy dirs)

```bash
SSH_ASKPASS=/tmp/sshpass.sh SSH_ASKPASS_REQUIRE=force \
  rsync -avz --exclude='.git/' --exclude='appdata/' --exclude='__pycache__/' \
  --exclude='datasets/' --exclude='logging/' --exclude='eval_*_logs/' \
  -e "ssh -i ~/.ssh/id_ed25519_mark" \
  guest@192.168.50.10:/home/aaron/BEHAVIOR-1K/ /destination/BEHAVIOR-1K/
```

## SLURM Status

aaron-workstation is part of the local SLURM cluster (192.168.50.x) but was DOWN as of 2026-03-31. The slurmd service may need restarting. This does not affect SSH access.
