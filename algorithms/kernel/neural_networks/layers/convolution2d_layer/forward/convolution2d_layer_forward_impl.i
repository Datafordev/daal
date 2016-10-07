/* file: convolution2d_layer_forward_impl.i */
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
//  Implementation of convolution2d algorithm
//--
*/

#include "service_tensor.h"
#include "service_numeric_table.h"

using namespace daal::internal;
using namespace daal::services;

namespace daal
{
namespace algorithms
{
namespace neural_networks
{
namespace layers
{
namespace convolution2d
{
namespace forward
{
namespace internal
{

template<typename algorithmFPType, Method method, CpuType cpu>
void Convolution2dKernel<algorithmFPType, method, cpu>::initialize(const services::Collection<size_t> inDimsFull, const services::Collection<size_t> wDims,
                                                                const convolution2d::Parameter *parameter, const services::Collection<size_t> outDimsFull)
{
    dnnError_t err;

    const size_t nGroups = parameter->nGroups;

    services::Collection<size_t> inDims (dimension);
    services::Collection<size_t> outDims(dimension);

    inDims  = inDimsFull ;
    outDims = outDimsFull;

    biasSize   [0] = parameter->nKernels;
    biasStrides[0] = 1;

    inputSize    [0] = inDims [dimension-1];
    inputStrides [0] = 1;
    outputSize   [0] = outDims[dimension-1];
    outputStrides[0] = 1;
    filterSize   [0] = wDims  [dimension-1];
    filterStrides[0] = 1;

    for(size_t i=1; i<dimension; i++)
    {
        inputSize    [i] = inDims [dimension-1-i];
        inputStrides [i] = inputStrides [i-1]*inputSize[i-1];
        outputSize   [i] = outDims[dimension-1-i];
        outputStrides[i] = outputStrides[i-1]*outputSize[i-1];
        filterSize   [i] = wDims  [dimension-1-i];
        filterStrides[i] = filterStrides[i-1]*filterSize[i-1];
    }

    convolutionStride[0] =   parameter->strides.size[1]  ;
    convolutionStride[1] =   parameter->strides.size[0]  ;
    inputOffset      [0] = -(parameter->paddings.size[1]);
    inputOffset      [1] = -(parameter->paddings.size[0]);

    ltUserInput  = xDnnLayout(dimension, inputSize,  inputStrides ); ON_ERR(ltUserInput .err);
    ltUserFilt   = xDnnLayout(dimension, filterSize, filterStrides); ON_ERR(ltUserFilt  .err);
    ltUserBias   = xDnnLayout(1,         biasSize,   biasStrides  ); ON_ERR(ltUserBias  .err);
    ltUserOutput = xDnnLayout(dimension, outputSize, outputStrides); ON_ERR(ltUserOutput.err);

    err = dnn::xConvolutionCreateForwardBias( &convPrim, dnnAlgorithmConvolutionDirect, nGroups, dimension, inputSize, outputSize,
        filterSize, convolutionStride, inputOffset, dnnBorderZeros);  ON_ERR(err);

    ltInnerInput  = xDnnLayout(convPrim, dnnResourceSrc   ); ON_ERR(ltInnerInput .err);
    ltInnerFilt   = xDnnLayout(convPrim, dnnResourceFilter); ON_ERR(ltInnerFilt  .err);
    ltInnerBias   = xDnnLayout(convPrim, dnnResourceBias  ); ON_ERR(ltInnerBias  .err);
    ltInnerOutput = xDnnLayout(convPrim, dnnResourceDst   ); ON_ERR(ltInnerOutput.err);
}

template<typename algorithmFPType, Method method, CpuType cpu>
void Convolution2dKernel<algorithmFPType, method, cpu>::compute(Tensor *inputTensor, Tensor *wTensor, Tensor *bTensor,
                                                                const convolution2d::Parameter *parameter, Tensor *resultTensor)
{
    dnnError_t err;

    const services::Collection<size_t>& inDimsFull  = inputTensor->getDimensions();
    const services::Collection<size_t>& wDims       = wTensor->getDimensions();
    const services::Collection<size_t>& bDims       = bTensor->getDimensions();
    const services::Collection<size_t>& outDimsFull = resultTensor->getDimensions();

    const size_t dimsArray[dimension] = { 0, parameter->groupDimension, parameter->indices.dims[0], parameter->indices.dims[1] };
    TensorOffsetLayout targetInLayout = inputTensor->createDefaultSubtensorLayout();
    targetInLayout.shuffleDimensions( services::Collection<size_t>( dimension, dimsArray ) );

    ReadSubtensor<algorithmFPType, cpu> inputBlock(inputTensor, 0, 0, 0, inDimsFull[0], targetInLayout);
    algorithmFPType *inputArray = const_cast<algorithmFPType*>(inputBlock.get());

    ReadSubtensor<algorithmFPType, cpu> wBlock(wTensor, 0, 0, 0, wDims[0]);
    algorithmFPType *wArray = const_cast<algorithmFPType*>(wBlock.get());

    ReadSubtensor<algorithmFPType, cpu> bBlock(bTensor, 0, 0, 0, bDims[0]);
    algorithmFPType *bArray = const_cast<algorithmFPType*>(bBlock.get());

    WriteOnlySubtensor<algorithmFPType, cpu> resultBlock(resultTensor, 0, 0, 0, outDimsFull[0]);
    algorithmFPType *resultArray = resultBlock.get();

    algorithmFPType* convRes[dnnResourceNumber] = {0};
    LayoutConvertor<algorithmFPType, cpu> cvToInnerInput(&inputArray, ltUserInput.get(), true, &convRes[dnnResourceSrc   ], ltInnerInput.get(), false); ON_ERR(cvToInnerInput.err);
    LayoutConvertor<algorithmFPType, cpu> cvToInnerFilt (&wArray    , ltUserFilt .get(), true, &convRes[dnnResourceFilter], ltInnerFilt .get(), false); ON_ERR(cvToInnerFilt .err);
    LayoutConvertor<algorithmFPType, cpu> cvToInnerBias (&bArray    , ltUserBias .get(), true, &convRes[dnnResourceBias  ], ltInnerBias .get(), false); ON_ERR(cvToInnerBias .err);

    xDnnBuffer dnnResourceDstBuffer(ltInnerOutput.get()); ON_ERR(dnnResourceDstBuffer.err);
    convRes[dnnResourceDst] = dnnResourceDstBuffer.get();

    LayoutConvertor<algorithmFPType, cpu> cvFromInnerOutput(&convRes[dnnResourceDst], ltInnerOutput.get(), false, &resultArray, ltUserOutput.get(), true); ON_ERR(cvFromInnerOutput.err);

    cvToInnerInput.convert(); ON_ERR(cvToInnerInput.err);
    cvToInnerFilt .convert(); ON_ERR(cvToInnerFilt .err);
    cvToInnerBias .convert(); ON_ERR(cvToInnerBias .err);

    err = dnn::xExecute(convPrim, (void**)convRes); ON_ERR(err);

    cvFromInnerOutput.convert(); ON_ERR(cvFromInnerOutput.err);
}

template<typename algorithmFPType, Method method, CpuType cpu>
void Convolution2dKernel<algorithmFPType, method, cpu>::reset()
{
    if(convPrim != NULL)
    {
        dnn::xDelete(convPrim);
    }
}

} // internal
} // forward
} // namespace convolution2d
} // namespace layers
} // namespace neural_networks
} // namespace algorithms
} // namespace daal
