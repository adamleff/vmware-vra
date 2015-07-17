require 'spec_helper'

describe Vra::Resource do
  let(:resource_id)       { '31a7badc-6562-458d-84f3-ec58d74a6953' }
  let(:vm_payload) do
    JSON.load(File.read(File.join(File.dirname(__FILE__),
                                  'fixtures',
                                  'resource',
                                  'vm_resource.json')))
  end

  let(:vm_payload_no_ops) do
    JSON.load(File.read(File.join(File.dirname(__FILE__),
                                  'fixtures',
                                  'resource',
                                  'vm_resource_no_operations.json')))
  end

  let(:non_vm_payload) do
    JSON.load(File.read(File.join(File.dirname(__FILE__),
                                  'fixtures',
                                  'resource',
                                  'non_vm_resource.json')))
  end

  describe '#initialize' do
    it 'raises an error if no ID or resource data have been provided' do
      expect { Vra::Resource.new }.to raise_error(ArgumentError)
    end

    it 'raises an error if an ID and resource data have both been provided' do
      expect { Vra::Resource.new(id: 123, data: 'foo') }.to raise_error(ArgumentError)
    end

    context 'when an ID is provided' do
      it 'calls fetch_resource_data' do
        resource = Vra::Resource.allocate
        expect(resource).to receive(:fetch_resource_data)
        resource.send(:initialize, @vra, id: resource_id)
      end
    end

    context 'when resource data is provided' do
      it 'populates the ID correctly' do
        resource = Vra::Resource.new(@vra, data: vm_payload)
        expect(resource.id).to eq resource_id
      end
    end
  end

  describe '#fetch_resource_data' do
    it 'calls http_get! against the resources API endpoint' do
      expect(@vra).to receive(:http_get!)
        .with("/catalog-service/api/consumer/resources/#{resource_id}")

      Vra::Resource.new(@vra, id: resource_id)
    end
  end

  context 'when a valid VM resource instance has been created' do
    before(:each) do
      @resource = Vra::Resource.new(@vra, data: vm_payload)
    end

    describe '#name' do
      it 'returns the correct name' do
        expect(@resource.name).to eq 'hol-dev-11'
      end
    end

    describe '#status' do
      it 'returns the correct status' do
        expect(@resource.status).to eq 'ACTIVE'
      end
    end

    describe '#vm?' do
      it 'returns true for the VM resource we created' do
        expect(@resource.vm?).to be true
      end
    end

    describe '#tenant_id' do
      it 'returns the correct tenant ID' do
        expect(@resource.tenant_id).to eq 'vsphere.local'
      end
    end

    describe '#tenant_name' do
      it 'returns the correct tenant name' do
        expect(@resource.tenant_name).to eq 'vsphere.local'
      end
    end

    describe '#subtenant_id' do
      it 'returns the correct subtenant ID' do
        expect(@resource.subtenant_id).to eq '5327ddd3-1a4e-4663-9e9d-63db86ffc8af'
      end
    end

    describe '#subtenant_name' do
      it 'returns the correct subtenant name' do
        expect(@resource.subtenant_name).to eq 'Rainpole Developers'
      end
    end

    describe '#network_interfaces' do
      it 'returns an array of 2 elements' do
        expect(@resource.network_interfaces.size).to be 2
      end

      it 'contains the correct data' do
        nic1, nic2 = @resource.network_interfaces

        expect(nic1['NETWORK_NAME']).to eq 'VM Network'
        expect(nic1['NETWORK_ADDRESS']).to eq '192.168.110.200'
        expect(nic1['NETWORK_MAC_ADDRESS']).to eq '00:50:56:ae:95:3c'

        expect(nic2['NETWORK_NAME']).to eq 'Management Network'
        expect(nic2['NETWORK_ADDRESS']).to eq '192.168.220.200'
        expect(nic2['NETWORK_MAC_ADDRESS']).to eq '00:50:56:ae:95:3d'
      end
    end

    describe '#ip_addresses' do
      it 'returns the correct IP addresses' do
        expect(@resource.ip_addresses).to eq [ '192.168.110.200', '192.168.220.200' ]
      end

      it 'returns nil if there are no network interfaces' do
        allow(@resource).to receive(:network_interfaces).and_return nil
        expect(@resource.ip_addresses).to be_nil
      end
    end

    describe '#actions' do
      it 'does not call #fetch_resource_data' do
        expect(@resource).not_to receive(:fetch_resource_data)
        @resource.actions
      end
    end

    describe '#action_id_by_name' do
      it 'returns the correct action ID for the destroy action' do
        expect(@resource.action_id_by_name('Destroy')).to eq 'ace8ba42-e724-48d8-9614-9b3a62b5a464'
      end

      it 'returns nil if there are no resource operations' do
        allow(@resource).to receive(:actions).and_return nil
        expect(@resource.action_id_by_name('Destroy')).to be_nil
      end

      it 'returns nil if there are actions, but none with the right name' do
        allow(@resource).to receive(:actions).and_return([ { 'name' => 'some action' }, { 'name' => 'another action' } ])
        expect(@resource.action_id_by_name('Destroy')).to be_nil
      end
    end

    describe '#destroy' do
      context 'when the destroy action is available' do
        it 'calls gets the action ID and submits the request' do
          expect(@resource).to receive(:action_id_by_name).with('Destroy').and_return('action-123')
          expect(@resource).to receive(:submit_action_request).with('action-123')
          @resource.destroy
        end
      end

      context 'when the destroy action is not available' do
        it 'raises an exception' do
          allow(@resource).to receive(:action_id_by_name).and_return nil
          expect { @resource.destroy }.to raise_error(Vra::Exception::NotFound)
        end
      end
    end

    describe '#submit_action_request' do
      before do
        allow(@resource).to receive(:action_request_payload).and_return({})
        response = double('response', code: 200, headers: { location: '/requests/request-12345' })
        allow(@vra).to receive(:http_post).with('/catalog-service/api/consumer/requests', '{}').and_return(response)
      end

      it 'calls http_post' do
        expect(@vra).to receive(:http_post).with('/catalog-service/api/consumer/requests', '{}')

        @resource.submit_action_request('action-123')
      end

      it 'returns a Vra::Request object' do
        expect(@resource.submit_action_request('action-123')).to be_an_instance_of(Vra::Request)
      end
    end
  end

  context 'when a valid VM resource instance with no operations is created' do
    before(:each) do
      @resource = Vra::Resource.new(@vra, data: vm_payload_no_ops)
    end

    describe '#actions' do
      it 'calls #fetch_resource_data' do
        expect(@resource).to receive(:fetch_resource_data)
        @resource.actions
      end
    end
  end

  context 'when a valid non-VM resource instance has been created' do
    before(:each) do
      @resource = Vra::Resource.new(@vra, data: non_vm_payload)
    end

    it 'returns nil for network_interfaces and ip_addresses' do
      expect(@resource.network_interfaces).to be_nil
      expect(@resource.ip_addresses).to be_nil
    end
  end
end
