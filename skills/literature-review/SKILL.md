---
name: literature-review
description: Conduct a structured literature review on a research topic. Use when surveying a field, finding related work, or building a bibliography for a paper.
license: MIT
metadata:
    skill-author: Embody AI
---

# Literature Review

Conduct a literature review on: $ARGUMENTS

## Workflow

### Phase 1: Scope
- Define the research question clearly
- Identify 3-5 seed papers (use /arxiv-search or user-provided references)
- Extract key terms and synonyms for comprehensive search

### Phase 2: Search
- Search across multiple sources:
  - arXiv (preprints, CS/physics/math/bio)
  - Semantic Scholar API: `https://api.semanticscholar.org/graph/v1/paper/search?query={query}&limit=20&fields=title,authors,year,abstract,citationCount`
  - Google Scholar (via web search)
- Snowball: check references of key papers and papers that cite them
- Target 20-50 relevant papers for a focused review

### Phase 3: Organize
Group papers into themes/categories. For each paper, extract:
- Core contribution (1 sentence)
- Method used
- Key results
- Limitations
- How it relates to the research question

### Phase 4: Synthesize
- Identify common findings and contradictions
- Note methodological trends
- Find gaps in the literature
- Summarize the state of the field

## Output Format

```markdown
## Literature Review: [Topic]

### Overview
[2-3 paragraph synthesis of the field]

### Key Themes

#### Theme 1: [name]
- Paper A (Author, Year): [contribution]
- Paper B (Author, Year): [contribution]
- **Synthesis**: [what these papers tell us together]

#### Theme 2: [name]
...

### Research Gaps
- [gap 1]
- [gap 2]

### Bibliography
1. Author et al. (Year). "Title." Venue. [link]
```

## Related

- See [references/search-sources.md](references/search-sources.md) for API details of each source
