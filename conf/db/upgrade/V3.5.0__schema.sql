ALTER TABLE VolumeSnapshotTreeEO ADD COLUMN status VARCHAR(32) NOT NULL DEFAULT "Completed";
DROP VIEW IF EXISTS `zstack`.`VolumeSnapshotTreeVO`;
CREATE VIEW `zstack`.`VolumeSnapshotTreeVO` AS SELECT uuid, volumeUuid, current, status, createDate, lastOpDate FROM `zstack`.`VolumeSnapshotTreeEO` WHERE deleted IS NULL;

ALTER TABLE `IAM2OrganizationVO` ADD COLUMN `rootOrganizationUuid` VARCHAR(32) NOT NULL;

DROP PROCEDURE IF EXISTS upgradeChild;
DROP PROCEDURE IF EXISTS upgradeOrganization;

DELIMITER $$
CREATE PROCEDURE upgradeChild(IN root_organization_uuid VARCHAR(32), IN current_organization_uuid VARCHAR(32))
    BEGIN
        DECLARE next_organization_uuid varchar(32);
        DECLARE done INT DEFAULT FALSE;
        DEClARE cur CURSOR FOR SELECT uuid FROM IAM2OrganizationVO WHERE parentUuid = current_organization_uuid;
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

        open cur;
        upgrade_child_loop: LOOP
            FETCH cur INTO next_organization_uuid;
            SELECT next_organization_uuid;
            IF done THEN
                LEAVE upgrade_child_loop;
            END IF;

            UPDATE IAM2OrganizationVO SET rootOrganizationUuid = root_organization_uuid WHERE uuid = next_organization_uuid;
            CALL upgradeChild(root_organization_uuid, next_organization_uuid);
        END LOOP;
        close cur;
        SELECT CURTIME();
    END $$
DELIMITER ;

DELIMITER $$
CREATE PROCEDURE upgradeOrganization()
    upgrade_procedure: BEGIN
        DECLARE root_organization_uuid VARCHAR(32);
        DECLARE null_root_organization_uuid_exists INT DEFAULT 0;
        DECLARE done INT DEFAULT FALSE;
        DEClARE cur CURSOR FOR SELECT uuid FROM IAM2OrganizationVO WHERE parentUuid is NULL;
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

        SELECT COUNT(uuid) INTO null_root_organization_uuid_exists FROM IAM2OrganizationVO where rootOrganizationUuid is NULL or rootOrganizationUuid = '';

        IF (null_root_organization_uuid_exists = 0) THEN
            SELECT CURTIME();
            LEAVE upgrade_procedure;
        END IF;

        OPEN cur;
        root_organization_loop: LOOP
            FETCH cur INTO root_organization_uuid;
            IF done THEN
                LEAVE root_organization_loop;
            END IF;

            UPDATE IAM2OrganizationVO SET rootOrganizationUuid = root_organization_uuid WHERE (rootOrganizationUuid is NULL or rootOrganizationUuid = '') and uuid = root_organization_uuid;
            CALL upgradeChild(root_organization_uuid, root_organization_uuid);
        END LOOP;
        CLOSE cur;
        SELECT CURTIME();
    END $$
DELIMITER ;

SET max_sp_recursion_depth=512;
call upgradeOrganization();
SET max_sp_recursion_depth=0;
DROP PROCEDURE IF EXISTS upgradeChild;
DROP PROCEDURE IF EXISTS upgradeOrganization;

DROP PROCEDURE IF EXISTS upgradeProjectAdmin;
DROP PROCEDURE IF EXISTS upgradeProjectOperator;
DROP PROCEDURE IF EXISTS upgradePlatformAdmin;
DROP PROCEDURE IF EXISTS getMaxAccountResourceRefVO;
DROP PROCEDURE IF EXISTS upgradePrivilegeAdmin;

-- upgrade project admin
DELIMITER $$
CREATE PROCEDURE upgradeProjectAdmin()
    BEGIN
        DECLARE done INT DEFAULT FALSE;
        DECLARE vid varchar(32);
        DECLARE count_new_attribute INT DEFAULT 0;
        DECLARE project_uuid varchar(32);
        DECLARE attribute_uuid VARCHAR(32);
        DECLARE cur CURSOR FOR SELECT virtualIDUuid,value FROM zstack.IAM2VirtualIDAttributeVO where name = '__ProjectAdmin__';
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

        OPEN cur;
        read_loop: LOOP
            FETCH cur INTO vid, project_uuid;
            IF done THEN
                LEAVE read_loop;
            END IF;

            SELECT count(*) into count_new_attribute from IAM2VirtualIDAttributeVO where name = '__IAM2ProjectAdmin__' and virtualIDUuid = vid;
            IF (count_new_attribute = 0) THEN
                SET attribute_uuid = REPLACE(UUID(), '-', '');

                INSERT INTO zstack.IAM2VirtualIDAttributeVO (`uuid`, `name`, `value`, `type`, `virtualIDUuid`, `lastOpDate`, `createDate`)
                VALUES (attribute_uuid, '__IAM2ProjectAdmin__', project_uuid, 'Customized', vid, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
            END IF;
        END LOOP;
        CLOSE cur;
        SELECT CURTIME();
    END $$
DELIMITER ;

-- upgrade project operator
DELIMITER $$
CREATE PROCEDURE upgradeProjectOperator()
    BEGIN
        DECLARE done INT DEFAULT FALSE;
        DECLARE vid varchar(32);
        DECLARE count_new_attribute INT DEFAULT 0;
        DECLARE project_uuid varchar(32);
        DECLARE attribute_uuid VARCHAR(32);
        DECLARE cur CURSOR FOR SELECT virtualIDUuid,value FROM zstack.IAM2VirtualIDAttributeVO where name = '__ProjectOperator__';
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

        OPEN cur;
        read_loop: LOOP
            FETCH cur INTO vid, project_uuid;
            IF done THEN
                LEAVE read_loop;
            END IF;

            SELECT count(*) into count_new_attribute from IAM2VirtualIDAttributeVO where name = '__IAM2ProjectOperator__' and virtualIDUuid = vid;

            IF (count_new_attribute = 0) THEN
                SET attribute_uuid = REPLACE(UUID(), '-', '');

                INSERT INTO zstack.IAM2VirtualIDAttributeVO (`uuid`, `name`, `value`, `type`, `virtualIDUuid`, `lastOpDate`, `createDate`)
                VALUES (attribute_uuid, '__IAM2ProjectOperator__', project_uuid, 'Customized', vid, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
            END IF;
        END LOOP;
        CLOSE cur;
        SELECT CURTIME();
    END $$
DELIMITER ;

-- upgrade platform admin
DELIMITER $$
CREATE PROCEDURE upgradePlatformAdmin()
    BEGIN
        DECLARE done INT DEFAULT FALSE;
        DECLARE count_new_attribute INT DEFAULT 0;
        DECLARE vid varchar(32);
        DECLARE attribute_uuid VARCHAR(32);
        DECLARE cur CURSOR FOR SELECT virtualIDUuid FROM zstack.IAM2VirtualIDAttributeVO where name = '__PlatformAdmin__';
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

        OPEN cur;
        read_loop: LOOP
            FETCH cur INTO vid;
            IF done THEN
                LEAVE read_loop;
            END IF;

            SELECT count(*) into count_new_attribute from IAM2VirtualIDAttributeVO where name = '__IAM2PlatformAdmin__' and virtualIDUuid = vid;
            IF (count_new_attribute = 0) THEN
                SET attribute_uuid = REPLACE(UUID(), '-', '');

                INSERT INTO zstack.IAM2VirtualIDAttributeVO (`uuid`, `name`, `value`, `type`, `virtualIDUuid`, `lastOpDate`, `createDate`)
                VALUES (attribute_uuid, '__IAM2PlatformAdmin__', NULL, 'Customized', vid, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
            END IF;
        END LOOP;
        CLOSE cur;
        SELECT CURTIME();
    END $$
DELIMITER ;

DELIMITER $$
CREATE PROCEDURE getMaxAccountResourceRefVO(OUT refId bigint(20) unsigned)
    BEGIN
        SELECT max(id) INTO refId from zstack.AccountResourceRefVO;
    END $$
DELIMITER ;

-- upgrade privilege admin
DELIMITER $$
CREATE PROCEDURE upgradePrivilegeAdmin(IN privilege_role_uuid VARCHAR(32), IN role_name VARCHAR(255))
    procedure_label: BEGIN
        DECLARE role_count INT DEFAULT 0;
        DECLARE done INT DEFAULT FALSE;
        DECLARE vid varchar(32);
        DECLARE role_statement_uuid varchar(32);
        DECLARE new_statement_uuid varchar(32);
        DECLARE refId bigint(20) unsigned;
        DECLARE generated_role_uuid VARCHAR(32);
        DECLARE cur CURSOR FOR SELECT virtualIDUuid FROM zstack.IAM2VirtualIDRoleRefVO WHERE roleUuid=privilege_role_uuid;
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
        SELECT count(*) INTO role_count FROM zstack.RoleVO WHERE uuid = privilege_role_uuid;

        IF (role_count = 0) THEN
            SELECT CURTIME();
            LEAVE procedure_label;
        END IF;

        SELECT uuid INTO role_statement_uuid FROM RolePolicyStatementVO WHERE roleUuid = privilege_role_uuid LIMIT 1;

        OPEN cur;
        read_loop: LOOP
            FETCH cur INTO vid;
            IF done THEN
                LEAVE read_loop;
            END IF;

            SET generated_role_uuid = REPLACE(UUID(), '-', '');

            INSERT INTO ResourceVO (`uuid`, `resourceName`, `resourceType`, `concreteResourceType`)
            VALUES (generated_role_uuid, role_name, 'RoleVO', 'org.zstack.header.identity.role.RoleVO');

            INSERT INTO zstack.RoleVO (`uuid`, `name`, `createDate`, `lastOpDate`, `state`, `type`)
            SELECT generated_role_uuid, role_name, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), `state`, 'Customized' FROM
            RoleVO WHERE uuid = privilege_role_uuid;

            CALL getMaxAccountResourceRefVO(refId);
            INSERT INTO AccountResourceRefVO (`id`, `accountUuid`, `ownerAccountUuid`, `resourceUuid`, `resourceType`, `permission`, `isShared`, `lastOpDate`, `createDate`)
            VALUES (refId + 1, '36c27e8ff05c4780bf6d2fa65700f22e', '36c27e8ff05c4780bf6d2fa65700f22e', generated_role_uuid, 'RoleVO', 2, 0, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

            SET new_statement_uuid = REPLACE(UUID(), '-', '');
            INSERT INTO zstack.RolePolicyStatementVO (`uuid`, `statement`, `roleUuid`, `lastOpDate`, `createDate`)
            SELECT new_statement_uuid, `statement`, generated_role_uuid, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP() FROM
            RolePolicyStatementVO WHERE uuid = role_statement_uuid;

            INSERT INTO IAM2VirtualIDRoleRefVO (`virtualIDUuid`, `roleUuid`, `lastOpDate`, `createDate`)
            VALUES (vid, generated_role_uuid, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
        END LOOP;
        CLOSE cur;

        DELETE FROM zstack.IAM2VirtualIDRoleRefVO WHERE roleUuid = privilege_role_uuid;
        DELETE FROM zstack.RolePolicyStatementVO WHERE roleUuid = privilege_role_uuid;
        DELETE FROM zstack.RoleVO WHERE uuid = privilege_role_uuid;
        DELETE FROM zstack.ResourceVO WHERE uuid = privilege_role_uuid;
        DELETE FROM zstack.AccountResourceRefVO WHERE resourceUuid = privilege_role_uuid;
        SELECT CURTIME();
    END $$
DELIMITER ;

CALL upgradeProjectAdmin();
CALL upgradeProjectOperator();
CALL upgradePlatformAdmin();
CALL upgradePrivilegeAdmin('434a5e418a114714848bb0923acfbb9c', 'audit-admin-role');
CALL upgradePrivilegeAdmin('58db081b0bbf4e93b63dc4ac90a423ad', 'security-admin-role');

DROP PROCEDURE IF EXISTS upgradeProjectAdmin;
DROP PROCEDURE IF EXISTS upgradeProjectOperator;
DROP PROCEDURE IF EXISTS upgradePlatformAdmin;
DROP PROCEDURE IF EXISTS getMaxAccountResourceRefVO;
DROP PROCEDURE IF EXISTS upgradePrivilegeAdmin;
