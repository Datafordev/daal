/* file: softmax_cross_layer_forward_impl.i */
/*******************************************************************************
* Copyright 2014-2017 Intel Corporation
* All Rights Reserved.
*
* If this  software was obtained  under the  Intel Simplified  Software License,
* the following terms apply:
*
* The source code,  information  and material  ("Material") contained  herein is
* owned by Intel Corporation or its  suppliers or licensors,  and  title to such
* Material remains with Intel  Corporation or its  suppliers or  licensors.  The
* Material  contains  proprietary  information  of  Intel or  its suppliers  and
* licensors.  The Material is protected by  worldwide copyright  laws and treaty
* provisions.  No part  of  the  Material   may  be  used,  copied,  reproduced,
* modified, published,  uploaded, posted, transmitted,  distributed or disclosed
* in any way without Intel's prior express written permission.  No license under
* any patent,  copyright or other  intellectual property rights  in the Material
* is granted to  or  conferred  upon  you,  either   expressly,  by implication,
* inducement,  estoppel  or  otherwise.  Any  license   under such  intellectual
* property rights must be express and approved by Intel in writing.
*
* Unless otherwise agreed by Intel in writing,  you may not remove or alter this
* notice or  any  other  notice   embedded  in  Materials  by  Intel  or Intel's
* suppliers or licensors in any way.
*
*
* If this  software  was obtained  under the  Apache License,  Version  2.0 (the
* "License"), the following terms apply:
*
* You may  not use this  file except  in compliance  with  the License.  You may
* obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
*
*
* Unless  required  by   applicable  law  or  agreed  to  in  writing,  software
* distributed under the License  is distributed  on an  "AS IS"  BASIS,  WITHOUT
* WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
*
* See the   License  for the   specific  language   governing   permissions  and
* limitations under the License.
*******************************************************************************/

/*
//++
//  Implementation of the forward softmax cross layer
//--
*/

#ifndef __SOFTMAX_CROSS_LAYER_FORWARD_IMPL_I__
#define __SOFTMAX_CROSS_LAYER_FORWARD_IMPL_I__

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
namespace loss
{
namespace softmax_cross
{
namespace forward
{
namespace internal
{

template<typename algorithmFPType, Method method, CpuType cpu>
services::Status SoftmaxCrossKernel<algorithmFPType, method, cpu>::compute(
    const Tensor &inputTensor,
    const Tensor &groundTruthTensor,
    const softmax_cross::Parameter &parameter,
    Tensor &probabilitiesTensor,
    Tensor &resultTensor)
{
    const algorithmFPType eps = parameter.accuracyThreshold;
    const size_t dim = parameter.dimension;

    const size_t nInputRows = inputTensor.getDimensionSize(0);

    size_t nBlocks = nInputRows / _nRowsInBlock;
    nBlocks += (nBlocks * _nRowsInBlock != nInputRows);

    daal::tls<algorithmFPType *> blockLoss( [ = ]()-> algorithmFPType*
    {
        algorithmFPType *partialLoss = new algorithmFPType;
        *partialLoss = 0;
        return partialLoss;
    } );

    __DAAL_MAKE_TENSOR_THREADSAFE(const_cast<Tensor *>(&inputTensor))
    __DAAL_MAKE_TENSOR_THREADSAFE(const_cast<Tensor *>(&groundTruthTensor))

    SafeStatus safeStat;
    daal::threader_for(nBlocks, nBlocks, [ =, &blockLoss, &safeStat, &inputTensor, &groundTruthTensor, &probabilitiesTensor ](int block)
    {
        size_t nRowsToProcess = _nRowsInBlock;
        if( block == nBlocks - 1 )
        {
            nRowsToProcess = nInputRows - block * _nRowsInBlock;
        }

        algorithmFPType *partialLoss = blockLoss.local();
        services::Status localStatus = processBlock(inputTensor, groundTruthTensor, block * _nRowsInBlock, nRowsToProcess, probabilitiesTensor, dim, eps, safeStat, *partialLoss);
        DAAL_CHECK_STATUS_THR(localStatus);
    }
                      );
    DAAL_CHECK_SAFE_STATUS();

    WriteOnlySubtensor<algorithmFPType, cpu> resultBlock(resultTensor, 0, 0, 0, 1);
    DAAL_CHECK_BLOCK_STATUS(resultBlock);
    algorithmFPType &loss = resultBlock.get()[0];
    loss = (algorithmFPType)0;

    blockLoss.reduce( [ =, &loss ](algorithmFPType * partialLoss)-> void
    {
        loss += (*partialLoss);
        delete partialLoss;
    }
                    );

    size_t dimsSize = inputTensor.getSize() / inputTensor.getDimensionSize(dim);
    loss = -1.0 * loss / dimsSize;

    return Status();
}

template<typename algorithmFPType, Method method, CpuType cpu>
inline Status SoftmaxCrossKernel<algorithmFPType, method, cpu>::processBlock(
    const Tensor &inputTensor,
    const Tensor &groundTruthTensor,
    const size_t nProcessedRows,
    const size_t nRowsInCurrentBlock,
    Tensor &probabilitiesTensor,
    const size_t dim,
    const algorithmFPType eps,
    SafeStatus &safeStat,
    algorithmFPType &partialLoss)
{
    WriteOnlySubtensor<algorithmFPType, cpu> probBlock(probabilitiesTensor, 0, 0, nProcessedRows, nRowsInCurrentBlock);
    DAAL_CHECK_BLOCK_STATUS(probBlock);
    algorithmFPType *probArray = probBlock.get();

    {
        ReadSubtensor<algorithmFPType, cpu> inputBlock(const_cast<Tensor &>(inputTensor), 0, 0, nProcessedRows, nRowsInCurrentBlock);
        DAAL_CHECK_BLOCK_STATUS(inputBlock);
        const algorithmFPType *inputArray = inputBlock.get();

        Collection<size_t> softmaxDim = inputTensor.getDimensions();
        softmaxDim[0] = nRowsInCurrentBlock;
        Status s;
        TensorPtr softmaxInput = HomogenTensor<algorithmFPType>::create(softmaxDim, const_cast<algorithmFPType *>(inputArray), &s);
        DAAL_CHECK_STATUS_VAR(s);
        TensorPtr softmaxProb = HomogenTensor<algorithmFPType>::create(softmaxDim, probArray, &s);
        DAAL_CHECK_STATUS_VAR(s);

        softmax::Parameter softmaxKernelParameter;
        softmaxKernelParameter.dimension = dim;
        softmaxKernelParameter.predictionStage = true;

        softmax::forward::internal::SoftmaxKernel<algorithmFPType, softmax::defaultDense, cpu> softmaxKernel;
        softmaxKernel.compute(*softmaxInput, softmaxKernelParameter, *softmaxProb);
    }

    ReadSubtensor<int, cpu> groundTruthBlock(const_cast<Tensor &>(groundTruthTensor), 0, 0, nProcessedRows, nRowsInCurrentBlock);
    DAAL_CHECK_BLOCK_STATUS(groundTruthBlock);
    const int *groundTruthArray = groundTruthBlock.get();

    const size_t dimensionSize = inputTensor.getDimensionSize(dim);
    const size_t offsetInclude = inputTensor.getSize(dim, inputTensor.getNumberOfDimensions() - dim);
    const size_t offsetAfter = offsetInclude / dimensionSize;
    const size_t offsetBeforeInRow = inputTensor.getSize() / offsetInclude / inputTensor.getDimensionSize(0);

    for(size_t j = 0; j < nRowsInCurrentBlock * offsetBeforeInRow; j++)
    {
        for(size_t k = 0; k < offsetAfter; k++)
        {
            partialLoss += Math<algorithmFPType, cpu>::sLog(Math<algorithmFPType, cpu>::sMax(probArray[(j * dimensionSize + groundTruthArray[j * offsetAfter + k]) * offsetAfter + k], eps));
        }
    }

    return Status();
}

} // namespace internal
} // namespace forward
} // namespace softmax_cross
} // namespace loss
} // namespace layers
} // namespace neural_networks
} // namespace algorithms
} // namespace daal

#endif
