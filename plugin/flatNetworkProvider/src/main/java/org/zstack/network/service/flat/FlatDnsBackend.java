package org.zstack.network.service.flat;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.annotation.Transactional;
import org.zstack.core.cloudbus.CloudBus;
import org.zstack.core.cloudbus.CloudBusListCallBack;
import org.zstack.core.db.DatabaseFacade;
import org.zstack.core.errorcode.ErrorFacade;
import org.zstack.header.core.Completion;
import org.zstack.header.core.NoErrorCompletion;
import org.zstack.header.errorcode.OperationFailureException;
import org.zstack.header.host.*;
import org.zstack.header.message.MessageReply;
import org.zstack.header.network.l3.L3NetworkInventory;
import org.zstack.header.network.service.DnsStruct;
import org.zstack.header.network.service.NetworkServiceDnsBackend;
import org.zstack.header.network.service.NetworkServiceProviderType;
import org.zstack.header.vm.VmInstanceSpec;
import org.zstack.kvm.*;
import org.zstack.utils.CollectionUtils;
import org.zstack.utils.Utils;
import org.zstack.utils.function.Function;
import org.zstack.utils.logging.CLogger;

import javax.persistence.TypedQuery;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Callable;

/**
 * Created by frank on 9/15/2015.
 */
public class FlatDnsBackend implements NetworkServiceDnsBackend, KVMHostConnectExtensionPoint, HostConnectionReestablishExtensionPoint {
    private static final CLogger logger = Utils.getLogger(FlatDnsBackend.class);

    @Autowired
    private CloudBus bus;
    @Autowired
    private ErrorFacade errf;
    @Autowired
    private DatabaseFacade dbf;

    public static final String SET_DNS_PATH = "/flatnetworkprovider/dns/set";

    @Transactional(readOnly = true)
    private List<String> getDnsByClusterUuid(String cuuid) {
        String sql = "select dns.dns from L3NetworkDnsVO dns, L3NetworkVO l3, L2NetworkClusterRefVO l2ref where" +
                " dns.l3NetworkUuid = l3.uuid and l3.l2NetworkUuid = l2ref.l2NetworkUuid and l2ref.clusterUuid = :cuuid";
        TypedQuery<String> q = dbf.getEntityManager().createQuery(sql, String.class);
        q.setParameter("cuuid", cuuid);
        return q.getResultList();
    }

    private void setDnsOnHost(HostInventory host) {
        List<String> dns = getDnsByClusterUuid(host.getClusterUuid());
        if (dns.isEmpty()) {
            return;
        }

        SetDnsCmd cmd = new SetDnsCmd();
        cmd.dns = dns;

        KVMHostAsyncHttpCallMsg msg = new KVMHostAsyncHttpCallMsg();
        msg.setHostUuid(host.getUuid());
        msg.setCommand(cmd);
        msg.setPath(SET_DNS_PATH);
        bus.makeTargetServiceIdByResourceUuid(msg, HostConstant.SERVICE_ID, host.getUuid());
        MessageReply reply = bus.call(msg);
        if (reply.isSuccess()) {
            throw new OperationFailureException(reply.getError());
        }

        KVMHostAsyncHttpCallReply re = (KVMHostAsyncHttpCallReply)reply;
        SetDnsRsp rsp = re.castReply();
        if (!rsp.isSuccess()) {
            throw new OperationFailureException(errf.stringToOperationError(rsp.getError()));
        }
    }

    @Override
    public void connectionReestablished(HostInventory inv) throws HostException {
        setDnsOnHost(inv);
    }

    @Override
    public HypervisorType getHypervisorTypeForReestablishExtensionPoint() {
        return KVMHostFactory.hypervisorType;
    }

    @Override
    public void kvmHostConnected(KVMHostConnectedContext context) throws KVMHostConnectException {
        setDnsOnHost(context.getInventory());
    }


    public static class SetDnsCmd extends KVMAgentCommands.AgentCommand {
        public List<String> dns;
    }

    public static class SetDnsRsp extends KVMAgentCommands.AgentResponse {
    }

    public NetworkServiceProviderType getProviderType() {
        return FlatNetworkServiceConstant.FLAT_NETWORK_SERVICE_TYPE;
    }

    private void setDns(final L3NetworkInventory l3, final List<String> dns, final Completion completion) {
        final List<String> hostUuids = new Callable<List<String>>() {
            @Override
            @Transactional(readOnly = true)
            public List<String> call() {
                String sql = "select h.uuid from HostVO h, L2NetworkClusterRefVO ref where h.clusterUuid = ref.clusterUuid" +
                        " and ref.l2NetworkUuid = :l2Uuid and h.status = :hstatus";
                TypedQuery<String> q = dbf.getEntityManager().createQuery(sql, String.class);
                q.setParameter("l2Uuid", l3.getL2NetworkUuid());
                q.setParameter("hstatus", HostStatus.Connected);
                return q.getResultList();
            }
        }.call();

        List<KVMHostAsyncHttpCallMsg> msgs = CollectionUtils.transformToList(hostUuids, new Function<KVMHostAsyncHttpCallMsg, String>() {
            @Override
            public KVMHostAsyncHttpCallMsg call(String huuid) {
                SetDnsCmd cmd = new SetDnsCmd();
                cmd.dns = dns;

                KVMHostAsyncHttpCallMsg msg = new KVMHostAsyncHttpCallMsg();
                msg.setCommand(cmd);
                msg.setPath(SET_DNS_PATH);
                msg.setHostUuid(huuid);
                bus.makeTargetServiceIdByResourceUuid(msg, HostConstant.SERVICE_ID, huuid);
                return msg;
            }
        });

        bus.send(msgs, new CloudBusListCallBack(completion) {
            @Override
            public void run(List<MessageReply> replies) {
                for (MessageReply reply : replies) {
                    String huuid = hostUuids.get(replies.indexOf(reply));
                    if (!reply.isSuccess()) {
                        //TODO
                        logger.warn(String.format("failed to apply dns%s to the kvm host[uuid:%s], %s", dns, huuid, reply.getError()));
                        continue;
                    }

                    KVMHostAsyncHttpCallReply re = reply.castReply();
                    SetDnsRsp rsp = re.toResponse(SetDnsRsp.class);
                    if (!rsp.isSuccess()) {
                        //TODO
                        logger.warn(String.format("failed to apply dns%s to the kvm host[uuid:%s], %s", dns, huuid, rsp.getError()));
                    }
                }

                completion.success();
            }
        });
    }

    @Override
    public void addDns(final L3NetworkInventory l3, final List<String> dns, final Completion completion) {
        setDns(l3, l3.getDns(), completion);
    }

    @Override
    public void removeDns(final L3NetworkInventory l3, List<String> dns, Completion completion) {
        List<String> newDns = new ArrayList<String>();
        newDns.addAll(l3.getDns());
        newDns.removeAll(dns);
        setDns(l3, newDns, completion);
    }

    @Override
    public void applyDnsService(List<DnsStruct> dnsStructList, VmInstanceSpec spec, Completion completion) {
        completion.success();
    }

    @Override
    public void releaseDnsService(List<DnsStruct> dnsStructsList, VmInstanceSpec spec, NoErrorCompletion completion) {
        completion.done();
    }
}
