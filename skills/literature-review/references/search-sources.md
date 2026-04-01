# Search Sources Reference

## Semantic Scholar API

```
GET https://api.semanticscholar.org/graph/v1/paper/search
```

| Parameter | Description |
|-----------|-------------|
| `query` | Search terms |
| `limit` | Results per page (max 100) |
| `offset` | Pagination offset |
| `fields` | Comma-separated: `title,authors,year,abstract,citationCount,url,externalIds` |
| `year` | Filter by year range: `2020-2024` |
| `fieldsOfStudy` | Filter: `Computer Science`, `Biology`, `Medicine`, etc. |

No API key required for basic usage. Rate limit: 100 requests/5 minutes.

## OpenAlex API

```
GET https://api.openalex.org/works?search={query}&per_page=25
```

Free, no key required. Covers 250M+ works. Supports filtering by concept, institution, journal, date.

## PubMed E-utilities

```
GET https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term={query}&retmax=20&retmode=json
```

For biomedical literature. Follow up with `efetch` to get abstracts. Free with API key for higher rate limits.

## CrossRef

```
GET https://api.crossref.org/works?query={query}&rows=20
```

DOI-based metadata for 150M+ records. Add `mailto` parameter for polite pool (faster responses).
