/* file: kernel_function_linear_csr_fast_impl.i */
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
//  Linear kernel functions implementation
//--
*/

#ifndef __KERNEL_FUNCTION_LINEAR_CSR_FAST_IMPL_I__
#define __KERNEL_FUNCTION_LINEAR_CSR_FAST_IMPL_I__

#include "kernel_function_types_linear.h"

#include "service_micro_table.h"

#include "kernel_function_csr_impl.i"

#include "threading.h"

namespace daal
{
namespace algorithms
{
namespace kernel_function
{
namespace linear
{
namespace internal
{

template <typename algorithmFPType, CpuType cpu>
void KernelImplLinear<fastCSR, algorithmFPType, cpu>::prepareData(
    CSRBlockMicroTable<algorithmFPType, readOnly,  cpu> &mtA1,
    CSRBlockMicroTable<algorithmFPType, readOnly,  cpu> &mtA2,
    BlockMicroTable<algorithmFPType, writeOnly, cpu> &mtR,
    const ParameterBase *svmPar,
    size_t *nVectors1, algorithmFPType **dataA1, size_t **colIndicesA1, size_t **rowOffsetsA1,
    size_t *nVectors2, algorithmFPType **dataA2, size_t **colIndicesA2, size_t **rowOffsetsA2,
    algorithmFPType **dataR, bool inputTablesSame)
{
    if(this->_computationMode == vectorVector)
    {
        prepareDataVectorVector(mtA1, mtA2, mtR, svmPar, nVectors1, dataA1, colIndicesA1, rowOffsetsA1,
                                nVectors2, dataA2, colIndicesA2, rowOffsetsA2, dataR, inputTablesSame);
    }
    else if(this->_computationMode == matrixVector)
    {
        prepareDataMatrixVector(mtA1, mtA2, mtR, svmPar, nVectors1, dataA1, colIndicesA1, rowOffsetsA1,
                                nVectors2, dataA2, colIndicesA2, rowOffsetsA2, dataR, inputTablesSame);
    }
    else if(this->_computationMode == matrixMatrix)
    {
        prepareDataMatrixMatrix(mtA1, mtA2, mtR, svmPar, nVectors1, dataA1, colIndicesA1, rowOffsetsA1,
                                nVectors2, dataA2, colIndicesA2, rowOffsetsA2, dataR, inputTablesSame);
    }
}

template <typename algorithmFPType, CpuType cpu>
void KernelImplLinear<fastCSR, algorithmFPType, cpu>::computeInternal(
    size_t nFeatures,
    size_t nVectors1, const algorithmFPType *dataA1, const size_t *colIndicesA1, const size_t *rowOffsetsA1,
    size_t nVectors2, const algorithmFPType *dataA2, const size_t *colIndicesA2, const size_t *rowOffsetsA2,
    algorithmFPType *dataR, const ParameterBase *par, bool inputTablesSame)
{
    if(this->_computationMode == vectorVector)
    {
        computeInternalVectorVector(nFeatures, nVectors1, dataA1, colIndicesA1, rowOffsetsA1,
                                    nVectors2, dataA2, colIndicesA2, rowOffsetsA2, dataR, par);
    }
    else if(this->_computationMode == matrixVector)
    {
        computeInternalMatrixVector(nFeatures, nVectors1, dataA1, colIndicesA1, rowOffsetsA1,
                                    nVectors2, dataA2, colIndicesA2, rowOffsetsA2, dataR, par);
    }
    else if(this->_computationMode == matrixMatrix)
    {
        computeInternalMatrixMatrix(nFeatures, nVectors1, dataA1, colIndicesA1, rowOffsetsA1,
                                    nVectors2, dataA2, colIndicesA2, rowOffsetsA2, dataR, par, inputTablesSame);
    }
}

template <typename algorithmFPType, CpuType cpu>
void KernelImplLinear<fastCSR, algorithmFPType, cpu>::computeInternalVectorVector(
    size_t nFeatures,
    size_t nVectors1, const algorithmFPType *dataA1, const size_t *colIndicesA1, const size_t *rowOffsetsA1,
    size_t nVectors2, const algorithmFPType *dataA2, const size_t *colIndicesA2, const size_t *rowOffsetsA2,
    algorithmFPType *dataR, const ParameterBase *par)
{
    const Parameter *linPar = static_cast<const Parameter *>(par);
    dataR[0] = computeDotProduct(rowOffsetsA1[0] - 1, rowOffsetsA1[1] - 1, dataA1, colIndicesA1,
                                 rowOffsetsA2[0] - 1, rowOffsetsA2[1] - 1, dataA2, colIndicesA2);
    dataR[0] = dataR[0] * linPar->k + linPar->b;
}

template <typename algorithmFPType, CpuType cpu>
void KernelImplLinear<fastCSR, algorithmFPType, cpu>::computeInternalMatrixVector(
    size_t nFeatures,
    size_t nVectors1, const algorithmFPType *dataA1, const size_t *colIndicesA1, const size_t *rowOffsetsA1,
    size_t nVectors2, const algorithmFPType *dataA2, const size_t *colIndicesA2, const size_t *rowOffsetsA2,
    algorithmFPType *dataR, const ParameterBase *par)
{
    const Parameter *linPar = static_cast<const Parameter *>(par);
    algorithmFPType b = (algorithmFPType)(linPar->b);
    algorithmFPType k = (algorithmFPType)(linPar->k);

    for (size_t i = 0; i < nVectors1; i++)
    {
        dataR[i] = computeDotProduct(rowOffsetsA1[i] - 1, rowOffsetsA1[i + 1] - 1, dataA1, colIndicesA1,
                                     rowOffsetsA2[0] - 1, rowOffsetsA2[1]   - 1, dataA2, colIndicesA2);
        dataR[i] = dataR[i] * k + b;
    }
}

template <typename algorithmFPType, CpuType cpu>
void KernelImplLinear<fastCSR, algorithmFPType, cpu>::computeInternalMatrixMatrix(
    size_t nFeatures,
    size_t nVectors1, const algorithmFPType *dataA1, const size_t *colIndicesA1, const size_t *rowOffsetsA1,
    size_t nVectors2, const algorithmFPType *dataA2, const size_t *colIndicesA2, const size_t *rowOffsetsA2,
    algorithmFPType *dataR, const ParameterBase *par, bool inputTablesSame)
{
    const Parameter *linPar = static_cast<const Parameter *>(par);
    algorithmFPType b = (algorithmFPType)(linPar->b);
    algorithmFPType k = (algorithmFPType)(linPar->k);

    if (inputTablesSame)
    {
        daal::threader_for_optional(nVectors1, nVectors1, [=](size_t i)
        {
            for (size_t j = 0; j <= i; j++)
            {
                dataR[i * nVectors1 + j] = computeDotProduct(rowOffsetsA1[i] - 1, rowOffsetsA1[i + 1] - 1, dataA1, colIndicesA1,
                                                             rowOffsetsA1[j] - 1, rowOffsetsA1[j + 1] - 1, dataA1, colIndicesA1);
                dataR[i * nVectors1 + j] = dataR[i * nVectors1 + j] * k + b;
            }
        } );
        daal::threader_for_optional(nVectors1, nVectors1, [=](size_t i)
        {
            for (size_t j = i + 1; j < nVectors1; j++)
            {
                dataR[i * nVectors1 + j] = dataR[j * nVectors1 + i];
            }
        } );
    }
    else
    {
        daal::threader_for_optional(nVectors1, nVectors1, [=](size_t i)
        {
            for (size_t j = 0; j < nVectors2; j++)
            {
                dataR[i * nVectors2 + j] = computeDotProduct(rowOffsetsA1[i] - 1, rowOffsetsA1[i + 1] - 1, dataA1, colIndicesA1,
                                                             rowOffsetsA2[j] - 1, rowOffsetsA2[j + 1] - 1, dataA2, colIndicesA2);
                dataR[i * nVectors2 + j] = dataR[i * nVectors2 + j] * k + b;
            }
        } );
    }
}

} // namespace internal

} // namespace linear

} // namespace kernel_function

} // namespace algorithms

} // namespace daal

#endif
