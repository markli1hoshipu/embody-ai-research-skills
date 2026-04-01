---
name: experiment-design
description: Design rigorous experiments with proper controls, metrics, and statistical analysis plans. Use when planning research experiments, A/B tests, or benchmark evaluations.
license: MIT
metadata:
    skill-author: Embody AI
---

# Experiment Design

Design an experiment for: $ARGUMENTS

## Process

### 1. Define the Hypothesis
- State the null hypothesis (H0) and alternative hypothesis (H1)
- Identify independent variables (what you change) and dependent variables (what you measure)
- List control variables (what you keep constant)

### 2. Choose the Design
- **Between-subjects**: different groups for each condition
- **Within-subjects**: same participants across conditions (watch for order effects)
- **Factorial**: multiple independent variables crossed
- **Ablation study**: remove components one at a time to measure contribution

### 3. Determine Sample Size
- Estimate expected effect size from prior work or pilot studies
- Choose significance level (typically α = 0.05)
- Choose desired power (typically 1-β = 0.80)
- Calculate minimum sample size

### 4. Define Metrics
- **Primary metric**: the one metric that answers your research question
- **Secondary metrics**: supporting evidence
- **Guardrail metrics**: things that must not degrade

### 5. Plan the Analysis
- Pre-register the analysis plan before running experiments
- Specify which statistical tests you will use
- Define what constitutes a meaningful result
- Plan for multiple comparison correction if testing many hypotheses

## Output Format

```markdown
## Experiment Plan: [Title]

**Hypothesis**: [H0 and H1]
**Design**: [between/within/factorial]
**Independent Variables**: [list]
**Dependent Variables**: [list with measurement methods]
**Controls**: [list]
**Sample Size**: [N with justification]
**Primary Metric**: [metric + success threshold]
**Statistical Test**: [test name + assumptions]
**Timeline**: [estimated duration]
**Risks**: [what could go wrong]
```
