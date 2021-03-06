require 'spec_helper'
require 'tempfile'

RSpec.describe 'exercising a device provider' do
  let(:common_args) { '--verbose --trace --strict=error --modulepath spec/fixtures' }

  before(:each) { skip 'No device --apply in the puppet gems yet' if ENV['PUPPET_GEM_VERSION'] }

  describe 'using `puppet resource`' do
    it 'reads resources from the target system' do
      stdout_str, status = Open3.capture2e("puppet resource #{common_args} device_provider")
      expected_values = 'device_provider { \"wibble\": \n  ensure => \'present\',\n  string => \'sample\',\n}'
      expect(stdout_str.strip).to match %r{\A(DL is deprecated, please use Fiddle\n)?#{expected_values}\Z}
      expect(status).to eq 0
    end
    it 'manages resources on the target system' do
      stdout_str, status = Open3.capture2e("puppet resource #{common_args} device_provider foo ensure=present")
      expect(stdout_str).to match %r{Notice: /Device_provider\[foo\]/ensure: defined 'ensure' as 'present'}
      expect(status).to eq 0
    end

    context 'with strict checking at error level' do
      let(:common_args) { '--verbose --trace --strict=error --modulepath spec/fixtures' }

      it 'deals with canonicalized resources correctly' do
        stdout_str, status = Open3.capture2e("puppet resource #{common_args} device_provider wibble ensure=present")
        stdmatch = 'Error: /Device_provider\[wibble\]: Could not evaluate: device_provider\[wibble\]#get has not provided canonicalized values.\n'\
                   'Returned values:       \{:name=>"wibble", :ensure=>:present, :string=>"sample"\}\n'\
                   'Canonicalized values:  \{:name=>"wibble", :ensure=>:present, :string=>"changed"\}'
        expect(stdout_str).to match %r{#{stdmatch}}
        expect(status.success?).to be_falsey # rubocop:disable RSpec/PredicateMatcher
      end
    end

    context 'with strict checking at warning level' do
      let(:common_args) { '--verbose --trace --strict=warning --modulepath spec/fixtures' }

      it 'deals with canonicalized resources correctly' do
        stdout_str, status = Open3.capture2e("puppet resource #{common_args} device_provider wibble ensure=present")
        stdmatch = 'Warning: device_provider\[wibble\]#get has not provided canonicalized values.\n'\
                   'Returned values:       \{:name=>"wibble", :ensure=>:present, :string=>"sample"\}\n'\
                   'Canonicalized values:  \{:name=>"wibble", :ensure=>:present, :string=>"changed"\}'
        expect(stdout_str).to match %r{#{stdmatch}}
        expect(status.success?).to be_truthy # rubocop:disable RSpec/PredicateMatcher
      end
    end

    context 'with strict checking turned off' do
      let(:common_args) { '--verbose --trace --strict=off --modulepath spec/fixtures' }

      it 'deals with canonicalized resources correctly' do
        stdout_str, status = Open3.capture2e("puppet resource #{common_args} device_provider wibble ensure=present")
        stdmatch = 'Notice: /Device_provider\[wibble\]/string: string changed \'sample\' to \'changed\''
        expect(stdout_str).to match %r{#{stdmatch}}
        expect(status.success?).to be_truthy # rubocop:disable RSpec/PredicateMatcher
      end
    end
  end
  describe 'using `puppet device`' do
    let(:common_args) { super() + ' --target the_node' }
    let(:device_conf) { Tempfile.new('device.conf') }
    let(:device_conf_content) do
      <<DEVICE_CONF
[the_node]
type test_device
url  file:///etc/credentials.txt
DEVICE_CONF
    end

    before(:each) do
      device_conf.write(device_conf_content)
      device_conf.close
    end

    after(:each) do
      device_conf.unlink
    end

    context 'with no config specified' do
      it 'errors out' do
        stdout_str, _status = Open3.capture2e("puppet device #{common_args}")
        expect(stdout_str).to match %r{Target device / certificate.*not found}
      end
    end

    it 'applies a catalog successfully' do
      stdout_str, _status = Open3.capture2e("puppet device #{common_args} --deviceconfig #{device_conf.path} --apply 'notify{\"foo\":}'")
      expect(stdout_str).to match %r{starting applying configuration to the_node at file:///etc/credentials.txt}
      expect(stdout_str).to match %r{defined 'message' as 'foo'}
      expect(stdout_str).not_to match %r{Error:}
    end

    it 'has the "foo" fact set to "bar"' do
      stdout_str, status = Open3.capture2e("puppet device #{common_args} --deviceconfig #{device_conf.path} --apply 'if $facts[\"foo\"] != \"bar\" { fail(\"fact not found\") }'")
      expect(stdout_str).not_to match %r{Error:}
      expect(status).to eq 0
    end

    context 'with a device resource in the catalog' do
      it 'applies the catalog successfully' do
        stdout_str, _status = Open3.capture2e("puppet device #{common_args} --deviceconfig #{device_conf.path} --apply 'device_provider{\"foo\": }'")
        expect(stdout_str).not_to match %r{Error:}
      end
    end
  end
end
