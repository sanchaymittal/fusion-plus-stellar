//! Timelock functionality for escrow contracts
//! Manages different phases of atomic swap lifecycle

use starknet::get_block_timestamp;

// Timelock stages equivalent to Solidity enum
#[derive(Drop, Serde, Copy, PartialEq)]
pub enum Stage {
    DstWithdrawal,
    DstPublicWithdrawal, 
    DstCancellation,
    SrcWithdrawal,
    SrcPublicWithdrawal,
    SrcCancellation,
    SrcPublicCancellation,
}


#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct Timelocks {
    pub deployed_at: u64,
    pub dst_withdrawal: u32,
    pub dst_public_withdrawal: u32,
    pub dst_cancellation: u32,
    pub src_withdrawal: u32,
    pub src_public_withdrawal: u32,
    pub src_cancellation: u32,
    pub src_public_cancellation: u32,
}

impl TimelocksPartialEq of PartialEq<Timelocks> {
    fn eq(lhs: @Timelocks, rhs: @Timelocks) -> bool {
        (*lhs).deployed_at == (*rhs).deployed_at
            && (*lhs).dst_withdrawal == (*rhs).dst_withdrawal
            && (*lhs).dst_public_withdrawal == (*rhs).dst_public_withdrawal
            && (*lhs).dst_cancellation == (*rhs).dst_cancellation
            && (*lhs).src_withdrawal == (*rhs).src_withdrawal
            && (*lhs).src_public_withdrawal == (*rhs).src_public_withdrawal
            && (*lhs).src_cancellation == (*rhs).src_cancellation
            && (*lhs).src_public_cancellation == (*rhs).src_public_cancellation
    }
}


#[generate_trait]
pub impl TimelocksImpl of TimelocksTrait {
    fn new(
        dst_withdrawal: u32,
        dst_public_withdrawal: u32, 
        dst_cancellation: u32,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
        src_public_cancellation: u32
    ) -> Timelocks {
        Timelocks {
            deployed_at: 0,
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
            src_public_cancellation,
        }
    }
    
    fn set_deployed_at(self: Timelocks, deployed_at: u64) -> Timelocks {
        Timelocks {
            deployed_at,
            dst_withdrawal: self.dst_withdrawal,
            dst_public_withdrawal: self.dst_public_withdrawal,
            dst_cancellation: self.dst_cancellation,
            src_withdrawal: self.src_withdrawal,
            src_public_withdrawal: self.src_public_withdrawal,
            src_cancellation: self.src_cancellation,
            src_public_cancellation: self.src_public_cancellation,
        }
    }
    
    fn get_deployed_at(self: @Timelocks) -> u64 {
        (*self).deployed_at
    }
    
    fn get_stage_time(self: @Timelocks, stage: Stage) -> u64 {
        let stage_delay = match stage {
            Stage::DstWithdrawal => (*self).dst_withdrawal,
            Stage::DstPublicWithdrawal => (*self).dst_public_withdrawal,
            Stage::DstCancellation => (*self).dst_cancellation,
            Stage::SrcWithdrawal => (*self).src_withdrawal,
            Stage::SrcPublicWithdrawal => (*self).src_public_withdrawal,
            Stage::SrcCancellation => (*self).src_cancellation,
            Stage::SrcPublicCancellation => (*self).src_public_cancellation,
        };
        
        let deployed_at = self.get_deployed_at();
        deployed_at + stage_delay.into()
    }
    
    fn rescue_start(self: @Timelocks, rescue_delay: u64) -> u64 {
        rescue_delay + self.get_deployed_at()
    }
    
    fn is_stage_active(self: @Timelocks, stage: Stage) -> bool {
        let current_time = get_block_timestamp();
        let stage_time = self.get_stage_time(stage);
        current_time >= stage_time
    }
    
    fn is_before_stage(self: @Timelocks, stage: Stage) -> bool {
        let current_time = get_block_timestamp();
        let stage_time = self.get_stage_time(stage);
        current_time < stage_time
    }
}

// Error definitions
pub mod Errors {
    pub const TOO_EARLY: felt252 = 'Too early for this operation';
    pub const TOO_LATE: felt252 = 'Too late for this operation';
    pub const INVALID_TIMELOCK: felt252 = 'Invalid timelock configuration';
}