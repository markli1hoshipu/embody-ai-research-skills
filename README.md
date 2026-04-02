# Embody AI Research Skills

AI research skills and agents for Claude Code, Codex, and other AI coding agents.

Embody provides its own research workflow skills and agents that **compose with** third-party skill libraries — particularly [K-Dense Scientific Skills](https://github.com/K-Dense-AI/claude-scientific-skills) (136+ scientific computing skills).

## Prerequisites

Install the following plugin for full agent functionality:

```bash
# K-Dense Scientific Skills (required by agents)
/plugin marketplace add K-Dense-AI/claude-scientific-skills
/plugin install scientific-skills@claude-scientific-skills --scope user
```

## Skills

| Skill | Description |
|-------|-------------|
| `arxiv-search` | Search arXiv for papers by topic, author, or ID |
| `paper-critique` | Critically evaluate research methodology and claims |
| `experiment-design` | Design rigorous experiments with controls and metrics |
| `literature-review` | Conduct structured literature reviews across sources |

## Agents

| Agent | Skills Used | Description |
|-------|-------------|-------------|
| `research-assistant` | arxiv-search, paper-critique, literature-review + K-Dense skills | End-to-end research exploration |
| `experiment-planner` | experiment-design, literature-review, arxiv-search + K-Dense skills | Design experiments grounded in prior work |

Agents compose Embody's own skills with K-Dense plugin skills (e.g. `scientific-skills:scanpy`, `scientific-skills:rdkit`). See [Prerequisites](#prerequisites).

## Install

### Claude Code (Plugin Marketplace)

```bash
/plugin marketplace add markli1hoshipu/embody-ai-research-skills
/plugin install embody-research-skills
```

### Manual (any agent)

```bash
git clone https://github.com/markli1hoshipu/embody-ai-research-skills.git
cd embody-ai-research-skills
bash install.sh --claude    # or --codex, --gemini
```

### Symlink (for development)

```bash
git clone https://github.com/markli1hoshipu/embody-ai-research-skills.git ~/embody-skills
ln -s ~/embody-skills/skills/* ~/.claude/skills/
ln -s ~/embody-skills/agents/* ~/.claude/agents/
```

## Structure

```
.claude-plugin/
    marketplace.json          # Claude plugin marketplace registration
skills/
    arxiv-search/
        SKILL.md              # Agent instructions
        references/           # API docs, detailed references
    paper-critique/
        SKILL.md
        references/
    experiment-design/
        SKILL.md
    literature-review/
        SKILL.md
        references/
agents/
    research-assistant.md     # Composes: arxiv-search + paper-critique + literature-review
    experiment-planner.md     # Composes: experiment-design + literature-review + arxiv-search
```

## Adding Your Own Skills

Create a new directory under `skills/` with a `SKILL.md`:

```yaml
---
name: your-skill-name
description: What it does and when to use it.
license: MIT
metadata:
    skill-author: Your Name
---

# Your Skill

Instructions for Claude go here.
$ARGUMENTS is replaced with user input.
```

## License

MIT
