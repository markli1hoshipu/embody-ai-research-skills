# arXiv API Reference

## Base URL

```
https://export.arxiv.org/api/query
```

## Query Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `search_query` | Search terms with field prefixes | `all:attention+AND+cat:cs.CL` |
| `id_list` | Comma-separated arXiv IDs | `2301.07041,2310.06825` |
| `start` | Offset for pagination | `0` |
| `max_results` | Number of results (max 100) | `10` |
| `sortBy` | Sort field: `relevance`, `lastUpdatedDate`, `submittedDate` | `submittedDate` |
| `sortOrder` | `ascending` or `descending` | `descending` |

## Field Prefixes

| Prefix | Field |
|--------|-------|
| `ti` | Title |
| `au` | Author |
| `abs` | Abstract |
| `co` | Comment |
| `jr` | Journal reference |
| `cat` | Category |
| `all` | All fields |

## Common Categories

- `cs.AI` — Artificial Intelligence
- `cs.CL` — Computation and Language (NLP)
- `cs.CV` — Computer Vision
- `cs.LG` — Machine Learning
- `stat.ML` — Machine Learning (Statistics)
- `q-bio` — Quantitative Biology
- `physics` — Physics (all)
- `cond-mat` — Condensed Matter

## Boolean Operators

Combine with `+AND+`, `+OR+`, `+ANDNOT+`:
```
search_query=au:bengio+AND+ti:attention+ANDNOT+cat:cs.CV
```

## Response Format

XML Atom feed. Each entry contains:
- `<title>` — paper title
- `<summary>` — abstract
- `<author><name>` — author names
- `<published>` — submission date (ISO 8601)
- `<link rel="alternate">` — abstract page URL
- `<link title="pdf">` — direct PDF link
- `<arxiv:primary_category>` — primary category

## Rate Limiting

- Respect 3-second delay between requests
- Bulk downloads should use the OAI-PMH interface instead
