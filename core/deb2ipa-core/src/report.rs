use serde::{Deserialize, Serialize};
use crate::planner::PlanOptions;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Blocking,
    Risky,
    Info,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversionWarning {
    pub severity: Severity,
    pub code: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversionReport {
    pub plan: PlanOptions,
    pub warnings: Vec<ConversionWarning>,
    pub gates_passed: bool,
    pub ipa_sha256: String,
}
