/* file: average_pooling2d_layer_forward_kernel.h */
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

//++
//  Declaration of template function that calculate forward pooling layer results.
//--

#ifndef __AVERAGE_POOLING2D_LAYER_FORWARD_KERNEL_H__
#define __AVERAGE_POOLING2D_LAYER_FORWARD_KERNEL_H__

#include "neural_networks/layers/pooling2d/average_pooling2d_layer_forward.h"
#include "neural_networks/layers/pooling2d/average_pooling2d_layer_forward_types.h"
#include "pooling2d_layer_internal_parameter.h"
#include "tensor.h"
#include "pooling2d_layer_forward_impl.i"

using namespace daal::data_management;
using namespace daal::services;

namespace daal
{
namespace algorithms
{
namespace neural_networks
{
namespace layers
{
namespace average_pooling2d
{
namespace forward
{
namespace internal
{

/**
 *  \brief Kernel for forward pooling layer results computation
 */
template<typename algorithmFPType, Method method, CpuType cpu>
class PoolingKernel : public pooling2d::forward::internal::PoolingKernel<algorithmFPType, cpu>
{
public:
    /* Computes the results of forward pooling layer */
    void compute(Tensor *dataTensor, const average_pooling2d::Parameter *parameter, Tensor *valueTensor);

protected:
    using pooling2d::forward::internal::PoolingKernel<algorithmFPType, cpu>::defaultCompute;

    virtual void defaultInnerLoop(pooling2d::internal::Parameter &par,
                DAAL_INT i, DAAL_INT f, DAAL_INT k, DAAL_INT s, DAAL_INT j,
                const algorithmFPType *data, algorithmFPType *valuePtr);

    virtual void defaultInnerLoop(pooling2d::internal::Parameter &par,
                DAAL_INT i, DAAL_INT f, DAAL_INT k, DAAL_INT s, DAAL_INT j,
                const algorithmFPType *data, algorithmFPType *valuePtr, int *selectedPos)
    {
        defaultInnerLoop(par, i, f, k, s, j, data, valuePtr);
    }
};

} // internal
} // forward
} // average_pooling2d
} // layers
} // neural_networks
} // algorithms
} // daal

#endif
