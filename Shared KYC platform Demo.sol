// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20 <0.9.0;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ConsortiumKYCRegistry
 * @notice 基于联盟链的去中心化 KYC 状态锚定与自动化验证引擎 (Demo)
 * @dev 设计原则：链下公钥验签 -> 链上合约查状态 -> 自动放行
 */
contract ConsortiumKYCRegistry is AccessControl {
    
    // 定义核心角色：一级持牌银行/发证机构
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    // KYC 核心状态数据结构（不含任何明文隐私数据）
    struct KYCRecord {
        bytes32 merkleRoot;      // 链下数据加盐后的 Merkle Root
        address issuer;          // 签发该凭证的一级机构地址
        uint64 issuedAt;         // 签发时间戳
        uint64 expiresAt;        // 凭证过期时间戳
        bool isRevoked;          // 风险撤销/冻结状态 (AML flag)
    }

    // 映射：用户地址/DID => KYC状态记录
    mapping(address => KYCRecord) private _kycRecords;

    // 事件：供二级机构业务后端实时监听
    event KYCAnchored(address indexed user, address indexed issuer, bytes32 merkleRoot, uint64 expiresAt);
    event KYCRevoked(address indexed user, address indexed revoker, string reason);
    event AutoCompliancePassed(address indexed user, address indexed verifier, uint256 timestamp);

    constructor(address defaultAdmin) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin); // 设置网络管理员（可为多签钱包）
    }

    // =========================================================
    // 模块 1：一级银行专有 - 链上身份状态锚定 (On-chain Anchoring)
    // =========================================================

    /**
     * @notice 持牌机构完成线下审核后，将状态锚定上链
     * @param user 用户的钱包地址或 DID 控制地址
     * @param merkleRoot 链下 Merkle Tree 的根哈希
     * @param validityDuration 凭证有效期（单位：秒）
     */
    function anchorKYC(
        address user,
        bytes32 merkleRoot,
        uint64 validityDuration
    ) external onlyRole(ISSUER_ROLE) {
        require(user != address(0), "Registry: Invalid user address");
        require(validityDuration > 0, "Registry: Invalid duration");
        
        uint64 issuedAt = uint64(block.timestamp);
        uint64 expiresAt = issuedAt + validityDuration;

        _kycRecords[user] = KYCRecord({
            merkleRoot: merkleRoot,
            issuer: msg.sender,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            isRevoked: false
        });

        emit KYCAnchored(user, msg.sender, merkleRoot, expiresAt);
    }

    // =========================================================
    // 模块 2：二级机构专用 - 自动化合规验证引擎 (Automated STP)
    // =========================================================

    /**
     * @notice 纯状态查询函数：检查链上锚定是否合法有效
     * @dev 前置条件：二级机构已在链下完成公钥验签与 Merkle 路径比对
     */
    function checkVerificationStatus(address user) public view returns (bool isVerified) {
        KYCRecord memory record = _kycRecords[user];

        // 逻辑判断 1：必须有签发机构，且该机构当前必须拥有 ISSUER_ROLE
        if (!hasRole(ISSUER_ROLE, record.issuer)) return false;

        // 逻辑判断 2：凭证不能处于主动撤销/洗钱冻结状态
        if (record.isRevoked) return false;

        // 逻辑判断 3：严格校验时间戳，必须在有效期内
        if (block.timestamp >= record.expiresAt) return false;

        return true;
    }

    /**
     * @notice 业务触发器：二级机构前端/后端调用此函数，满足条件即自动打通业务权限
     */
    function executeAutomatedOnboarding(address user) external returns (bool) {
        // 自动调用裁决引擎
        bool verified = checkVerificationStatus(user);
        
        // 若状态无效，交易将回滚（Revert），拦截违规开户
        require(verified, "KYC Registry: Record is Expired, Revoked, or Invalid");

        // 若执行到此，代表身份核验 100% 成功。
        // 此处可接续实际的业务逻辑：例如解锁跨国转账限额、记录合规审计日志等
        
        emit AutoCompliancePassed(user, msg.sender, block.timestamp);
        return true;
    }

    // =========================================================
    // 模块 3：风控与合规更新 - 动态撤销机制 (Revocation)
    // =========================================================

    /**
     * @notice AML 风控阻断：当查实用户涉嫌洗钱时，原签发机构可全网同步撤销其合规状态
     */
    function revokeKYC(address user, string calldata reason) external onlyRole(ISSUER_ROLE) {
        require(_kycRecords[user].issuer == msg.sender, "Registry: Only the original issuer can revoke");
        require(!_kycRecords[user].isRevoked, "Registry: Already revoked");
        
        // 更新状态，切断该用户在全网所有机构的业务权限
        _kycRecords[user].isRevoked = true;

        emit KYCRevoked(user, msg.sender, reason);
    }
}
