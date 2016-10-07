/* file: neural_networks_training_batch_container.h */
/*******************************************************************************
* Copyright 2014-2016 Intel Corporation
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*******************************************************************************/

/*
//++
//  Implementation of neural_networks calculation algorithm container.
//--
*/

#ifndef __NEURAL_NETWORKS_TRAINING_BATCH_CONTAINER_H__
#define __NEURAL_NETWORKS_TRAINING_BATCH_CONTAINER_H__

#include "neural_networks/neural_networks_training.h"
#include "neural_networks_types.h"
#include "neural_networks_training_types.h"
#include "neural_networks_training_feedforward_kernel.h"
#include "kernel.h"

namespace daal
{
namespace algorithms
{
namespace neural_networks
{
namespace training
{
namespace interface1
{
template<typename algorithmFPType, Method method, CpuType cpu>
BatchContainer<algorithmFPType, method, cpu>::BatchContainer(daal::services::interface1::Environment::env *daalEnv)
{
    __DAAL_INITIALIZE_KERNELS(internal::TrainingKernelBatch, algorithmFPType, method);
}

template<typename algorithmFPType, Method method, CpuType cpu>
BatchContainer<algorithmFPType, method, cpu>::~BatchContainer()
{
    __DAAL_DEINITIALIZE_KERNELS();
}

template<typename algorithmFPType, Method method, CpuType cpu>
void BatchContainer<algorithmFPType, method, cpu>::compute()
{
    Input *input = static_cast<Input *>(_in);
    Result *result = static_cast<Result *>(_res);

    daal::services::Environment::env &env = *_env;

    Tensor* data = input->get(training::data).get();
    Model* nnModel = result->get(training::model).get();
    KeyValueDataCollectionPtr groundTruthCollectionPtr = input->get(training::groundTruthCollection);

    __DAAL_CALL_KERNEL(env, internal::TrainingKernelBatch, __DAAL_KERNEL_ARGUMENTS(algorithmFPType, method), compute,
                       data, nnModel, groundTruthCollectionPtr);
}

template<typename algorithmFPType, Method method, CpuType cpu>
void BatchContainer<algorithmFPType, method, cpu>::setupCompute()
{
    Input *input = static_cast<Input *>(_in);
    Result *result = static_cast<Result *>(_res);

    Parameter *parameter = static_cast<Parameter *>(_par);
    daal::services::Environment::env &env = *_env;

    Tensor* data = input->get(training::data).get();
    Model* nnModel = result->get(training::model).get();
    KeyValueDataCollectionPtr groundTruthCollectionPtr = input->get(training::groundTruthCollection);

    __DAAL_CALL_KERNEL(env, internal::TrainingKernelBatch, __DAAL_KERNEL_ARGUMENTS(algorithmFPType, method), initialize,
                       data, nnModel, groundTruthCollectionPtr, parameter);
}

template<typename algorithmFPType, Method method, CpuType cpu>
void BatchContainer<algorithmFPType, method, cpu>::resetCompute()
{
    daal::services::Environment::env &env = *_env;
    __DAAL_CALL_KERNEL(env, internal::TrainingKernelBatch, __DAAL_KERNEL_ARGUMENTS(algorithmFPType, method), reset);
}

} // namespace interface1
} // namespace training
} // namespace neural_networks
} // namespace algorithms
} // namespace daal

#endif
