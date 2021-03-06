package org.zstack.compute.vm;

import org.springframework.beans.factory.annotation.Autowire;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Configurable;
import org.zstack.core.cloudbus.CloudBus;
import org.zstack.core.cloudbus.CloudBusCallBack;
import org.zstack.core.db.DatabaseFacade;
import org.zstack.header.core.workflow.FlowTrigger;
import org.zstack.header.core.workflow.NoRollbackFlow;
import org.zstack.header.message.MessageReply;
import org.zstack.header.storage.primary.InstantiateVolumeMsg;
import org.zstack.header.storage.primary.InstantiateVolumeReply;
import org.zstack.header.storage.primary.PrimaryStorageConstant;
import org.zstack.header.storage.primary.PrimaryStorageInventory;
import org.zstack.header.vm.VmInstanceConstant;
import org.zstack.header.vm.VmInstanceSpec;
import org.zstack.header.volume.VolumeFormat;
import org.zstack.header.volume.VolumeInventory;
import org.zstack.header.volume.VolumeStatus;
import org.zstack.header.volume.VolumeVO;

import java.util.Map;

@Configurable(preConstruction = true, autowire = Autowire.BY_TYPE)
public class VmInstantiateAttachingVolumeFlow extends NoRollbackFlow {
    @Autowired
    protected DatabaseFacade dbf;
    @Autowired
    protected CloudBus bus;

    @Override
    public void run(final FlowTrigger chain, final Map ctx) {
        final VolumeInventory volume = (VolumeInventory) ctx.get(VmInstanceConstant.Params.AttachingVolumeInventory.toString());
        final VmInstanceSpec spec = (VmInstanceSpec) ctx.get(VmInstanceConstant.Params.VmInstanceSpec.toString());
        assert volume != null;
        assert spec != null;

        final PrimaryStorageInventory pinv = (PrimaryStorageInventory) ctx.get(VmInstanceConstant.Params.DestPrimaryStorageInventoryForAttachingVolume.toString());
        volume.setPrimaryStorageUuid(pinv.getUuid());
        InstantiateVolumeMsg msg = new InstantiateVolumeMsg();
        msg.setDestHost(spec.getDestHost());
        msg.setVolume(volume);
        bus.makeTargetServiceIdByResourceUuid(msg, PrimaryStorageConstant.SERVICE_ID, pinv.getUuid());
        bus.send(msg, new CloudBusCallBack(chain) {
            @Override
            public void run(MessageReply reply) {
                if (reply.isSuccess()) {
                    InstantiateVolumeReply r = (InstantiateVolumeReply) reply;
                    VolumeVO vo = dbf.findByUuid(r.getVolume().getUuid(), VolumeVO.class);
                    vo.setPrimaryStorageUuid(pinv.getUuid());
                    vo.setInstallPath(r.getVolume().getInstallPath());
                    vo.setFormat(r.getVolume().getFormat());
                    if (vo.getFormat() == null) {
                        vo.setFormat(VolumeFormat.getVolumeFormatByMasterHypervisorType(spec.getVmInventory().getHypervisorType()).toString());
                    }
                    vo.setStatus(VolumeStatus.Ready);
                    vo = dbf.updateAndRefresh(vo);
                    ctx.put(VmInstanceConstant.Params.AttachingVolumeInventory.toString(), VolumeInventory.valueOf(vo));
                    chain.next();
                } else {
                    chain.fail(reply.getError());
                }
            }
        });
    }
}
