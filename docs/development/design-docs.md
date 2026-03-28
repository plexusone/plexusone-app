# Design Documents

Index of design documents for Nexus features and architecture.

## Current Documents

### Core Platform

| Document | Description | Status |
|----------|-------------|--------|
| [PRD](../design/prd.md) | Product Requirements Document | Active |
| [TRD](../design/trd.md) | Technical Requirements Document | Active |

### Features

| Document | Description | Status |
|----------|-------------|--------|
| [Mobile App PRD](../design/FEAT_MOBILE_PRD.md) | Mobile companion app design | In Progress |
| [AgentPair Design](../design/FEAT_AGENTPAIR_DESIGN.md) | AgentPair integration analysis | Planned |
| [Sentinel PRD](../design/FEAT_SENTINEL_PRD.md) | Agent monitoring feature | Planned |
| [VoiceNote PRD](../design/FEAT_VOICENOTE_PRD.md) | Voice note integration | Planned |

### Implementation

| Document | Description | Status |
|----------|-------------|--------|
| [Scrollbar Research](../design/FEAT_SCROLLBAR_RESEARCH.md) | Terminal scrollbar investigation | Completed |
| [Scrollbar TRD](../design/FEAT_SCROLLBAR_TRD.md) | Scrollbar fix implementation design | Completed |

## Document Structure

### Product Requirements Document (PRD)

PRDs define what we're building and why:

```markdown
# Feature Name PRD

## Problem Statement
What problem are we solving?

## Goals
- Primary objectives
- Success metrics

## Non-Goals
What we're explicitly not doing

## User Stories
As a [user], I want to [action] so that [benefit]

## Requirements
### Functional Requirements
### Non-Functional Requirements

## Design
High-level design approach

## Open Questions
Unresolved decisions
```

### Technical Requirements Document (TRD)

TRDs define how we're building it:

```markdown
# Feature Name TRD

## Overview
Technical summary

## Architecture
- System diagram
- Component responsibilities
- Data flow

## API Design
- Endpoints
- Message formats
- Error handling

## Implementation Plan
- Phases
- Dependencies
- Risks

## Testing Strategy
- Unit tests
- Integration tests
- Performance tests
```

## Creating New Documents

### When to Write a Design Doc

Write a design doc when:

- Adding a significant new feature
- Making architectural changes
- Introducing new dependencies
- Changing external interfaces

### Process

1. **Create draft** in `docs/design/`
2. **Name format**: `FEAT_<NAME>_PRD.md` or `FEAT_<NAME>_TRD.md`
3. **Review** with stakeholders
4. **Iterate** based on feedback
5. **Approve** before implementation
6. **Update** as implementation reveals new information

### Template

Create new PRDs using this structure:

```markdown
# [Feature Name] PRD

**Author:** [Your name]
**Status:** Draft | Review | Approved | Implemented
**Created:** YYYY-MM-DD
**Updated:** YYYY-MM-DD

## Problem Statement

[Describe the problem]

## Goals

1. [Goal 1]
2. [Goal 2]

## Non-Goals

- [Non-goal 1]

## Background

[Context and prior art]

## Proposed Solution

[High-level approach]

## Detailed Design

[Specifics]

## Alternatives Considered

### Alternative 1
[Description and why rejected]

## Open Questions

- [ ] Question 1
- [ ] Question 2

## References

- [Link 1]
```

## Archived Documents

Documents for completed or abandoned features are moved to `docs/design/archive/`.

## Related

- [Architecture](architecture.md) - System architecture overview
- [Contributing](contributing.md) - How to contribute
