package org.zstack.storage.backup.sftp;

import org.zstack.header.configuration.PythonClass;

@PythonClass
public interface SftpBackupStorageConstant {
    public static final String SERVICE_ID = "storage.backup.sftp";
    
    @PythonClass
    public static final String SFTP_BACKUP_STORAGE_TYPE = "SftpBackupStorage";
    
    public static final String CONNECT_PATH = "/sftpbackupstorage/connect";
    public static final String DOWNLOAD_IMAGE_PATH = "/sftpbackupstorage/download";
    public static final String DELETE_PATH = "/sftpbackupstorage/delete";
    public static final String PING_PATH = "/sftpbackupstorage/ping";
    public static final String ECHO_PATH = "/sftpbackupstorage/echo";
    public static final String GET_SSHKEY_PATH = "/sftpbackupstorage/sshkey";
    public static final String WRITE_IMAGE_METADATA = "/sftpbackupstorage/writeimagemetadata";
    public static final String ANSIBLE_PLAYBOOK_NAME = "sftpbackupstorage.yaml";
    public static final String ANSIBLE_MODULE_PATH = "ansible/sftpbackupstorage";
}
