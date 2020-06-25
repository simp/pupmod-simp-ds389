# frozen_string_literal: true

require 'spec_helper'

describe 'ds389::install' do
  context 'when on supported operating systems' do
    on_supported_os.each do |os, os_facts|
      before(:each) do
        Puppet::Parser::Functions.newfunction(:assert_private, type: :rvalue) { |args| }
      end

      let(:facts) do
        os_facts.merge({
                         'ds389::package_ensure' => 'present'
                       })
      end

      context "with #{os}" do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('389-ds-base').with_ensure('present') }
        it { is_expected.not_to contain_package('389-admin') }
        it { is_expected.not_to contain_package('389-admin-console') }
        it { is_expected.not_to contain_package('389-ds-console') }

        context 'with admin enabled' do
          let(:params) do
            {
              enable_admin_service: true
            }
          end

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_package('389-admin').with_ensure('present') }
          it { is_expected.to contain_package('389-admin-console').with_ensure('present') }
          it { is_expected.to contain_package('389-ds-console').with_ensure('present') }
          it { is_expected.not_to contain_package('389-ds-base').with_ensure('present') }
        end
      end
    end
  end
end
