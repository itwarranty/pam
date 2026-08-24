## MODIFIED Requirements

### Requirement: Policy v2 SHALL decide before forwarding a logical command

The PTY inspector SHALL buffer a complete logical command and evaluate policy
before command bytes or the submit terminator are forwarded to the child PTY.

#### Scenario: Allowed command
- **WHEN** an operator submits a command that does not match a deny rule
- **THEN** the inspector SHALL forward the command exactly once
- **AND** normal terminal output and exit status SHALL be preserved

#### Scenario: Denied command
- **WHEN** an operator submits a command matching a deny rule
- **THEN** no byte of that logical command or its line terminator SHALL reach
  the child PTY
- **AND** no target-side history entry or side effect SHALL occur
- **AND** telemetry SHALL contain `policy=v2` and the effective mode

#### Scenario: Multi-line paste
- **WHEN** bracketed or ordinary paste contains multiple logical lines
- **THEN** every line SHALL be evaluated independently before forwarding
- **AND** a denied line SHALL NOT cause adjacent allowed lines to bypass policy

### Requirement: Policy v2 SHALL preserve terminal semantics safely

The PTY relay SHALL preserve documented interactive terminal behavior without
allowing control sequences to bypass command policy.

#### Scenario: Ctrl+C
- **WHEN** Ctrl+C is entered with pending input
- **THEN** the pending local buffer SHALL be cleared
- **AND** the inspector SHALL NOT terminate with a traceback
- **AND** an appropriate interrupt SHALL reach a running child command

#### Scenario: Ctrl+D
- **WHEN** Ctrl+D is entered
- **THEN** EOF behavior SHALL match the documented shell behavior
- **AND** buffered denied input SHALL NOT be committed

#### Scenario: Terminal resize
- **WHEN** the outer terminal emits SIGWINCH
- **THEN** rows and columns SHALL be propagated to the child PTY

#### Scenario: Cursor Position Report
- **WHEN** the client/IDE injects `ESC[row;colR`
- **THEN** the sequence SHALL NOT become shell input
- **AND** filtering SHALL NOT remove unrelated valid CSI sequences

#### Scenario: Inspector exit
- **WHEN** the child exits, the client disconnects, or a signal/exception occurs
- **THEN** outer terminal attributes SHALL be restored

### Requirement: Legacy command policy v1 SHALL require explicit waiver

Production use of the remote-shell policy v1 fallback SHALL be fail-closed
unless an explicit migration waiver is configured.

#### Scenario: Production selects v1
- **WHEN** command policy v2 is disabled in a production profile
- **THEN** preflight SHALL fail unless an explicit time-bounded v1 waiver is
  configured
- **AND** runtime telemetry SHALL identify `policy=v1`
