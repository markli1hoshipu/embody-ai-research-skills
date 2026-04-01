---
name: paper-critique
description: Critically evaluate a research paper's methodology, results, and claims. Use when reviewing papers, assessing study quality, or preparing peer review feedback.
license: MIT
metadata:
    skill-author: Embody AI
---

# Paper Critique

Critically evaluate the research paper: $ARGUMENTS

## Evaluation Framework

Assess the paper across these dimensions:

### 1. Research Question & Motivation
- Is the problem clearly defined?
- Is there a gap in existing literature that justifies this work?
- Are the claims appropriately scoped?

### 2. Methodology
- Is the approach sound and well-justified?
- Are baselines appropriate and sufficient?
- Are there confounding variables unaccounted for?
- Is the experimental setup reproducible?

### 3. Results & Analysis
- Do the results support the claims?
- Are statistical tests appropriate (p-values, confidence intervals, effect sizes)?
- Are negative results reported honestly?
- Are ablation studies included where appropriate?

### 4. Limitations & Threats to Validity
- Are limitations acknowledged?
- Internal validity: could other factors explain the results?
- External validity: do results generalize beyond the specific setup?

### 5. Writing & Presentation
- Is the paper clearly written?
- Are figures informative and properly labeled?
- Is related work comprehensive and fair?

## Output Format

```markdown
## Paper Critique: [Title]

**Summary**: [1-2 sentence summary of what the paper does]

**Strengths**:
- [strength 1]
- [strength 2]

**Weaknesses**:
- [weakness 1 with specific evidence]
- [weakness 2 with specific evidence]

**Questions for Authors**:
- [question 1]

**Overall Assessment**: [Strong Accept / Accept / Weak Accept / Borderline / Weak Reject / Reject]

**Confidence**: [High / Medium / Low]
```

## Related

- See [references/review-checklist.md](references/review-checklist.md) for domain-specific checklists
