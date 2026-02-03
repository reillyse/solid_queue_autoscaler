# frozen_string_literal: true

RSpec.describe SolidQueueAutoscaler::AutoscaleJob do
  describe '#normalize_worker_name' do
    let(:job) { described_class.new }

    context 'with a symbol argument' do
      it 'returns the symbol unchanged' do
        expect(job.send(:normalize_worker_name, :all)).to eq(:all)
        expect(job.send(:normalize_worker_name, :default)).to eq(:default)
        expect(job.send(:normalize_worker_name, :priority_worker)).to eq(:priority_worker)
      end
    end

    context 'with a string that looks like a symbol (YAML misconfiguration)' do
      it 'raises ConfigurationError for ":all"' do
        expect { job.send(:normalize_worker_name, ':all') }
          .to raise_error(SolidQueueAutoscaler::ConfigurationError, /received string ":all" instead of symbol :all/)
      end

      it 'raises ConfigurationError for ":default"' do
        expect { job.send(:normalize_worker_name, ':default') }
          .to raise_error(SolidQueueAutoscaler::ConfigurationError, /received string ":default" instead of symbol :default/)
      end

      it 'raises ConfigurationError for ":priority_worker"' do
        expect { job.send(:normalize_worker_name, ':priority_worker') }
          .to raise_error(SolidQueueAutoscaler::ConfigurationError, /received string ":priority_worker" instead of symbol :priority_worker/)
      end

      it 'includes YAML fix instructions in the error message' do
        expect { job.send(:normalize_worker_name, ':all') }
          .to raise_error(SolidQueueAutoscaler::ConfigurationError, /In your recurring.yml, change:/)
      end

      it 'suggests removing quotes from the symbol' do
        expect { job.send(:normalize_worker_name, ':all') }
          .to raise_error(SolidQueueAutoscaler::ConfigurationError, /Remove the quotes around the symbol/)
      end

      it 'shows the correct before/after YAML syntax' do
        expect { job.send(:normalize_worker_name, ':all') }
          .to raise_error(SolidQueueAutoscaler::ConfigurationError) do |error|
            expect(error.message).to include('- ":all"')
            expect(error.message).to include('- :all')
          end
      end
    end

    context 'with a plain string (lenient mode)' do
      it 'converts to a symbol' do
        expect(job.send(:normalize_worker_name, 'default')).to eq(:default)
        expect(job.send(:normalize_worker_name, 'priority_worker')).to eq(:priority_worker)
        expect(job.send(:normalize_worker_name, 'all')).to eq(:all)
      end
    end
  end
end
