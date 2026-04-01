---
name: arxiv-search
description: Search arXiv for academic papers by topic, author, or ID. Use when doing literature review, finding related work, or looking up specific papers.
license: MIT
metadata:
    skill-author: Embody AI
---

# arXiv Paper Search

Search arXiv for papers matching: $ARGUMENTS

## Workflow

1. **Parse the query** — identify whether the user wants to search by topic, author name, or arXiv ID (e.g., `2301.07041`)
2. **Search arXiv** — use the arXiv API via web fetch:
   - By topic: `https://export.arxiv.org/api/query?search_query=all:{query}&max_results=10&sortBy=submittedDate&sortOrder=descending`
   - By ID: `https://export.arxiv.org/api/query?id_list={id}`
   - By author: `https://export.arxiv.org/api/query?search_query=au:{name}&max_results=10`
3. **Parse the XML response** — extract title, authors, abstract, published date, and PDF link for each result
4. **Present results** in a structured table:

| # | Title | Authors | Date | arXiv ID |
|---|-------|---------|------|----------|
| 1 | ...   | ...     | ...  | ...      |

5. **If the user asks for details** on a specific paper, fetch and summarize the abstract

## Tips

- Combine search terms with `+AND+` for precise results: `search_query=all:transformer+AND+all:protein`
- Use `cat:cs.AI` for category-specific searches
- arXiv rate limits: wait 3 seconds between requests
- For very recent papers (last 24h), results may not yet be indexed

## Related

- See [references/arxiv-api.md](references/arxiv-api.md) for full API documentation
