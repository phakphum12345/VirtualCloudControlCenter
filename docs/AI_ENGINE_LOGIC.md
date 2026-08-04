# AI Engine Logic

## Purpose

The AI engine translates user intent into a safe, validated, auditable application action or response. It is not permitted to execute unrestricted commands directly.

## Components

### Command parser

Responsibilities:

- normalize Thai and English input
- identify command candidates
- extract entities and parameters
- distinguish conversation from executable intent
- return a typed parse result with confidence and errors

### Context builder

Responsibilities:

- load only relevant settings, capabilities, memory, and recent results
- exclude secrets and unrelated personal data
- apply context-size limits
- record which context sources were used

### Risk classifier

Suggested levels:

- `low`: read-only, reversible, no sensitive disclosure
- `medium`: writes local state or changes settings
- `high`: destructive, external, privileged, financial, identity, or privacy-sensitive
- `blocked`: violates policy or platform safety boundaries

### Permission policy

The permission layer evaluates:

- whether the capability is available
- whether the user authorized it
- whether confirmation is required
- whether the platform grants the native permission
- whether emergency stop is active

### Planner

The planner produces a finite ordered plan. Every step includes:

- action identifier
- required capability
- input parameters
- expected result
- reversibility
- confirmation requirement
- failure behavior

### Command validator

Validation occurs before execution and checks:

- supported action
- complete parameters
- parameter bounds
- path and destination allowlists
- permission decision
- risk decision
- confirmation state
- dependency availability

### Provider router

The router chooses an AI provider adapter according to user configuration and capability. It must:

- avoid hard-coding a single provider
- use a common request/response interface
- return clear quota, authentication, network, and timeout errors
- never place provider secrets in logs
- never embed private keys in a Web release

### Executor

The executor runs only validated plan steps. It must stop on:

- emergency stop
- permission revocation
- validation failure
- unexpected capability change
- unrecoverable step failure

### Verifier

The verifier compares actual outcomes to expected outcomes and reports:

- success
- partial success
- failed with no change
- failed with possible partial change
- unsupported
- cancelled

### Audit logger

Each meaningful operation records:

- timestamp
- action identifier
- risk level
- permission decision
- confirmation state
- result status
- non-secret summary

## End-to-end flow

```text
receive input
→ normalize
→ parse
→ decide chat or action
→ build minimum context
→ search approved memory
→ classify risk
→ evaluate permission
→ produce finite plan
→ validate every step
→ request confirmation when required
→ execute
→ verify
→ audit
→ format user response
→ persist only approved memory
```

## Memory rules

Memory is explicit, limited, and user-controllable.

Store only when information is useful beyond the current turn and permitted by the user or product policy. Do not store:

- access tokens
- API keys
- passwords or PINs
- full sensitive documents without explicit need
- transient error dumps

Memory lifecycle:

```text
candidate
→ sensitivity check
→ deduplicate
→ assign scope and retention
→ encrypt when appropriate
→ store
→ retrieve by relevance
→ update or expire
→ user-visible deletion
```

## Automation rules

Automations are stored tasks with explicit trigger, scope, and cancellation. They must not be represented as unrestricted background agents.

Required fields:

- task id
- user-visible title
- trigger or schedule
- allowed action set
- required permissions
- next run
- last result
- enabled state

## Failure model

The engine must return structured failures rather than generic server messages:

- `networkUnavailable`
- `providerAuthenticationFailed`
- `providerQuotaExceeded`
- `providerTimeout`
- `permissionDenied`
- `confirmationRequired`
- `unsupportedCapability`
- `invalidCommand`
- `validationFailed`
- `executionFailed`
- `cancelled`
- `emergencyStopActive`

## Offline behavior

Without a network connection, the application must continue to support local rule-based commands, local storage, local search, settings, audit history, and platform capabilities that do not require the internet. Provider-dependent operations return a precise offline result.

## Testing requirements

- parser tests for Thai and English
- planner determinism tests
- risk classification boundary tests
- permission default-deny tests
- validator rejection tests
- executor cancellation tests
- emergency-stop tests
- audit redaction tests
- provider adapter error mapping tests
- memory retention and deletion tests
