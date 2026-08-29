%%% Bit flags for `mailbox_state''s status field. Powers of 2, per
%%% evoq_bit_flags convention -- see reckon-db-org/evoq's guides/bit_flags.md
%%% and this workspace's own guide_repo_lifecycle (repo_status.hrl).
-define(MAILBOX_INITIATED, 1). %% 2^0 -- the aggregate exists
-define(MAILBOX_OPEN,      2). %% 2^1 -- currently receiving mail
-define(MAILBOX_ARCHIVED,  4). %% 2^2 -- terminal, unless unarchived
