/* file: kdtree_knn_classification_train_dense_default_impl.i */
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
//  Implementation of auxiliary functions for K-Nearest Neighbors K-D Tree (kDTreeDense) method.
//--
*/

#ifndef __KDTREE_KNN_CLASSIFICATION_TRAIN_DENSE_DEFAULT_IMPL_I__
#define __KDTREE_KNN_CLASSIFICATION_TRAIN_DENSE_DEFAULT_IMPL_I__

#define KNN_INT_RANDOM_NUMBER_GENERATOR

#include "daal_defines.h"
#include "threading.h"
#include "daal_atomic_int.h"
#include "service_memory.h"
#include "service_data_utils.h"
#include "service_math.h"
#include "service_rng.h"
#include "service_sort.h"
#include "numeric_table.h"
#include "kdtree_knn_classification_model_impl.h"
#include "kdtree_knn_classification_train_kernel.h"
#include "kdtree_knn_impl.i"

#if defined(__INTEL_COMPILER_BUILD_DATE)
#include <immintrin.h>
#endif

namespace daal
{
namespace algorithms
{
namespace kdtree_knn_classification
{
namespace training
{
namespace internal
{

using namespace daal::services::internal;
using namespace daal::services;
using namespace daal::internal;
using namespace kdtree_knn_classification::internal;

template <typename T, CpuType cpu>
class Queue
{
public:
    Queue() : _data(nullptr)
    {
    }

    ~Queue()
    {
        services::daal_free(_data);
    }

    bool init(size_t size)
    {
        clear();
        _first = _count = 0;
        _last = _sizeMinus1 = (_size = size) - 1;
        return ((_data = static_cast<T *>(daal_malloc(size * sizeof(T)))) != nullptr);
    }

    void clear()
    {
        daal_free(_data);
        _data = nullptr;
    }

    void reset()
    {
        _first = _count = 0;
        _last = _sizeMinus1;
    }

    DAAL_FORCEINLINE void push(const T & value)
    {
        _data[_last = (_last + 1) & _sizeMinus1] = value;
        ++_count;
    }

    DAAL_FORCEINLINE T pop()
    {
        const T value = _data[_first++];
        _first *= (_first != _size);
        --_count;
        return value;
    }

    bool empty() const { return (_count == 0); }

    size_t size() const { return _count; }

private:
    T * _data;
    size_t _first;
    size_t _last;
    size_t _count;
    size_t _size;
    size_t _sizeMinus1;
};

struct BuildNode
{
    size_t start;
    size_t end;
    size_t nodePos;
    size_t queueOrStackPos;
};

template <typename T>
struct BoundingBox
{
    T lower;
    T upper;
};

template <typename algorithmFpType, CpuType cpu>
struct IndexValuePair
{
    algorithmFpType value;
    size_t idx;

    inline bool operator< (const IndexValuePair & rhs) const { return (value < rhs.value); }
};

template <typename algorithmFpType, CpuType cpu>
int compareIndexValuePair(const void * p1, const void * p2)
{
    typedef IndexValuePair<algorithmFpType, cpu> IVPair;

    const IVPair & v1 = *static_cast<const IVPair *>(p1);
    const IVPair & v2 = *static_cast<const IVPair *>(p2);
    return (v1.value < v2.value) ? -1 : 1;
}

template <typename algorithmFpType, CpuType cpu>
void KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    compute(NumericTable * x, NumericTable * y, kdtree_knn_classification::Model * r, const daal::algorithms::Parameter * par)
{
    typedef daal::internal::Math<algorithmFpType, cpu> Math;
    typedef BoundingBox<algorithmFpType> BBox;

    const kdtree_knn_classification::Parameter * const parameter = static_cast<const kdtree_knn_classification::Parameter *>(par);

    const size_t xRowCount = x->getNumberOfRows();
    const size_t xColumnCount = x->getNumberOfColumns();
    r->setNFeatures(xColumnCount);

    const algorithmFpType base = 2.0;
    const size_t maxKDTreeNodeCount = ((size_t)Math::sPowx(base, Math::sCeil(Math::sLog(base * xRowCount - 1) / Math::sLog(base)))
        * __KDTREE_MAX_NODE_COUNT_MULTIPLICATION_FACTOR) / __KDTREE_LEAF_BUCKET_SIZE + 1;
    r->impl()->setKDTreeTable(SharedPtr<KDTreeTable>(new KDTreeTable(maxKDTreeNodeCount)));

    size_t * const indexes  = static_cast<size_t *>(daal_malloc(xRowCount * sizeof(size_t)));
    for (size_t i = 0; i < xRowCount; ++i)
    {
        indexes[i] = i;
    }

    Queue<BuildNode, cpu> q;
    BBox * bboxQ = nullptr;

    buildFirstPartOfKDTree(q, bboxQ, *x, *r, indexes, parameter->seed);
    buildSecondPartOfKDTree(q, bboxQ, *x, *r, indexes, parameter->seed);
    rearrangePoints(*x, indexes);
    rearrangePoints(*y, indexes);

    daal_free(bboxQ);
    daal_free(indexes);
}

template <typename algorithmFpType, CpuType cpu>
void KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    buildFirstPartOfKDTree(Queue<BuildNode, cpu> & q, BoundingBox<algorithmFpType> * & bboxQ, const NumericTable & x,
                           kdtree_knn_classification::Model & r, size_t * indexes, int seed)
{
    typedef daal::internal::Math<algorithmFpType, cpu> Math;
    typedef BoundingBox<algorithmFpType> BBox;

    const auto maxThreads = threader_get_threads_number();
    const algorithmFpType base = 2.0;
    const size_t queueSize = 2 * Math::sPowx(base, Math::sCeil(Math::sLog(__KDTREE_FIRST_PART_LEAF_NODES_PER_THREAD * maxThreads)
                                                               / Math::sLog(base)));
    const size_t firstPartLeafNodeCount = queueSize / 2;
    q.init(queueSize);
    const size_t xColumnCount = x.getNumberOfColumns();
    const size_t xRowCount = x.getNumberOfRows();
    const size_t bboxSize = queueSize * xColumnCount;
    bboxQ = static_cast<BBox *>(daal_malloc(bboxSize * sizeof(BBox), sizeof(BBox)));
    r.impl()->setLastNodeIndex(0);
    r.impl()->setRootNodeIndex(0);
    BBox * bboxCur = nullptr;
    BBox * bboxLeft = nullptr;
    BBox * bboxRight = nullptr;
    BuildNode bn, bnLeft, bnRight;
    bn.start = 0;
    bn.end = xRowCount;
    bn.nodePos = r.impl()->getLastNodeIndex();
    r.impl()->setLastNodeIndex(bn.nodePos + 1);
    bn.queueOrStackPos = bn.nodePos;
    bboxCur = &bboxQ[bn.queueOrStackPos * xColumnCount];
    computeLocalBoundingBoxOfKDTree(bboxCur, x, indexes);

    q.push(bn);

    size_t depth = 0;
    size_t maxNodeCountForCurrentDepth = 1;

    size_t sophisticatedSampleIndexes[__KDTREE_DIMENSION_SELECTION_SIZE];
    algorithmFpType sophisticatedSampleValues[__KDTREE_DIMENSION_SELECTION_SIZE];
    const size_t subSampleCount = xRowCount / __KDTREE_SEARCH_SKIP + 1;
    algorithmFpType * subSamples = static_cast<algorithmFpType *>(daal_malloc(subSampleCount * sizeof(algorithmFpType)));

    while (maxNodeCountForCurrentDepth < firstPartLeafNodeCount)
    {
        for (size_t i = 0; i < maxNodeCountForCurrentDepth; ++i)
        {
            bn = q.pop();
            KDTreeNode & curNode = *(static_cast<KDTreeNode *>(r.impl()->getKDTreeTable()->getArray()) + bn.nodePos);
            bboxCur = &bboxQ[bn.queueOrStackPos * xColumnCount];
            if (bn.end - bn.start > __KDTREE_LEAF_BUCKET_SIZE)
            {
                const size_t d = selectDimensionSophisticated(bn.start, bn.end, sophisticatedSampleIndexes, sophisticatedSampleValues,
                                                              __KDTREE_DIMENSION_SELECTION_SIZE, x, indexes, seed);
                const algorithmFpType approximatedMedian = computeApproximatedMedianInParallel(bn.start, bn.end, d, bboxCur[d].upper, x, indexes,
                                                                                               seed, subSamples, subSampleCount);
                const size_t idx = adjustIndexesInParallel(bn.start, bn.end, d, approximatedMedian, x, indexes);
                curNode.cutPoint = approximatedMedian;
                curNode.dimension = d;
                size_t nodeIdx = r.impl()->getLastNodeIndex();
                curNode.leftIndex = nodeIdx++;
                curNode.rightIndex = nodeIdx++;
                r.impl()->setLastNodeIndex(nodeIdx);

                bnLeft.start = bn.start;
                bnLeft.end = idx;
                bnLeft.queueOrStackPos = bnLeft.nodePos = curNode.leftIndex;
                bboxLeft = &bboxQ[bnLeft.queueOrStackPos * xColumnCount];
                copyBBox(bboxLeft, bboxCur, xColumnCount);
                bboxLeft[d].upper = approximatedMedian;
                q.push(bnLeft);

                bnRight.start = idx;
                bnRight.end = bn.end;
                bnRight.queueOrStackPos = bnRight.nodePos = curNode.rightIndex;
                bboxRight = &bboxQ[bnRight.queueOrStackPos * xColumnCount];
                copyBBox(bboxRight, bboxCur, xColumnCount);
                bboxRight[d].lower = approximatedMedian;
                q.push(bnRight);
            }
            else
            { // Should be leaf node.
                curNode.cutPoint = 0;
                curNode.dimension = __KDTREE_NULLDIMENSION;
                curNode.leftIndex = bn.start;
                curNode.rightIndex = bn.end;

                if (q.empty())
                {
                    break;
                }
            }
        }

        if (q.empty())
        {
            break;
        }

        ++depth;
        maxNodeCountForCurrentDepth = static_cast<size_t>(1) << depth;
    }

    daal_free(subSamples);
}

template <typename algorithmFpType, CpuType cpu>
void KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    computeLocalBoundingBoxOfKDTree(BoundingBox<algorithmFpType> * bbox, const NumericTable & x, const size_t * indexes)
{
    typedef BoundingBox<algorithmFpType> BBox;
    typedef daal::data_feature_utils::internal::MaxVal<algorithmFpType, cpu> MaxVal;

    const size_t xRowCount = x.getNumberOfRows();
    const size_t xColumnCount = x.getNumberOfColumns();

    const size_t rowsPerBlock = 128;
    const size_t blockCount = (xRowCount + rowsPerBlock - 1) / rowsPerBlock;
    data_management::BlockDescriptor<algorithmFpType> columnBD;
    for (size_t j = 0; j < xColumnCount; ++j)
    {
        bbox[j].upper = - MaxVal::get();
        bbox[j].lower = MaxVal::get();

        const_cast<NumericTable &>(x).getBlockOfColumnValues(j, 0, xRowCount, readOnly, columnBD);
        const algorithmFpType * const dx = columnBD.getBlockPtr();

        daal::tls<BBox *> bboxTLS([=]()-> BBox *
        {
            BBox * const ptr = service_scalable_calloc<BBox, cpu>(1);
            if (ptr)
            {
                ptr->lower = MaxVal::get();
                ptr->upper = - MaxVal::get();
            }
            else { _errors->add(services::ErrorMemoryAllocationFailed); }
            return ptr;
        } );

        daal::threader_for(blockCount, blockCount, [=, &bboxTLS](int iBlock)
        {
            BBox * const bboxLocal = bboxTLS.local();
            if (bboxLocal)
            {
                const size_t first = iBlock * rowsPerBlock;
                const size_t last = min<cpu>(static_cast<decltype(xRowCount)>(first + rowsPerBlock), xRowCount);

                if (first < last)
                {
                    BBox b;
                    size_t i = first;
                    b.upper = dx[indexes[i]];
                    b.lower = dx[indexes[i]];
                    PRAGMA_IVDEP
                    for (++i; i < last; ++i)
                    {
                        if (b.lower > dx[indexes[i]]) { b.lower = dx[indexes[i]]; }
                        if (b.upper < dx[indexes[i]]) { b.upper = dx[indexes[i]]; }
                    }

                    if (bboxLocal->upper < b.upper) { bboxLocal->upper = b.upper; }
                    if (bboxLocal->lower > b.lower) { bboxLocal->lower = b.lower; }
                }
            }
        } );

        bboxTLS.reduce([=](BBox * v) -> void
        {
            if (v)
            {
                if (bbox[j].lower > v->lower) { bbox[j].lower = v->lower; }
                if (bbox[j].upper < v->upper) { bbox[j].upper = v->upper; }
                service_scalable_free<BBox, cpu>(v);
            }
        } );

        const_cast<NumericTable &>(x).releaseBlockOfColumnValues(columnBD);
    }
}

template <typename algorithmFpType, CpuType cpu>
size_t KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    selectDimensionSophisticated(size_t start, size_t end, size_t * sampleIndexes, algorithmFpType * sampleValues, size_t sampleCount,
                                 const NumericTable & x, const size_t * indexes, int seed)
{
    const size_t elementCount = min<cpu>(end - start, sampleCount);
    const size_t xColumnCount = x.getNumberOfColumns();
    const size_t xRowCount = x.getNumberOfRows();

    algorithmFpType maxVarianceValue = 0;
    size_t maxVarianceDim = 0;

    if (end - start < sampleCount)
    {
        data_management::BlockDescriptor<algorithmFpType> columnBD;
        for (size_t j = 0; j < xColumnCount; ++j)
        {
            const_cast<NumericTable &>(x).getBlockOfColumnValues(j, 0, xRowCount, readOnly, columnBD);
            const algorithmFpType * const dx = columnBD.getBlockPtr();

            PRAGMA_IVDEP
            for (size_t i = 0; i < elementCount; ++i)
            {
                sampleValues[i] = dx[indexes[start + i]];
            }

            algorithmFpType meanValue = 0;

            for (size_t i = 0; i < elementCount; ++i)
            {
                meanValue += sampleValues[i];
            }

            meanValue /= static_cast<algorithmFpType>(elementCount);

            algorithmFpType varValue = 0;
            for (size_t i = 0; i < elementCount; ++i)
            {
                varValue += (sampleValues[i] - meanValue) * (sampleValues[i] - meanValue);
            }

            if (varValue > maxVarianceValue)
            {
                maxVarianceValue = varValue;
                maxVarianceDim = j;
            }

            const_cast<NumericTable &>(x).releaseBlockOfColumnValues(columnBD);
        }
    }
    else
    {
        daal::internal::BaseRNGs<cpu> brng(seed);
#ifdef KNN_INT_RANDOM_NUMBER_GENERATOR
        daal::internal::RNGs<int, cpu> rng;
        int * const tempSampleIndexes = static_cast<int *>(daal_malloc(elementCount * sizeof(*tempSampleIndexes)));
        rng.uniform(elementCount, tempSampleIndexes, brng, start, end);
        for (size_t i = 0; i < elementCount; ++i) { sampleIndexes[i] = tempSampleIndexes[i]; }
        daal_free(tempSampleIndexes);
#else
        daal::internal::RNGs<size_t, cpu> rng;
        rng.uniform(elementCount, sampleIndexes, brng, start, end);
#endif
        data_management::BlockDescriptor<algorithmFpType> columnBD;
        for (size_t j = 0; j < xColumnCount; ++j)
        {
            const_cast<NumericTable &>(x).getBlockOfColumnValues(j, 0, xRowCount, readOnly, columnBD);
            const algorithmFpType * const dx = columnBD.getBlockPtr();

            PRAGMA_SIMD_ASSERT
            for (size_t i = 0; i < elementCount; ++i)
            {
                sampleValues[i] = dx[indexes[sampleIndexes[i]]];
            }

            algorithmFpType meanValue = 0;

            for (size_t i = 0; i < elementCount; ++i)
            {
                meanValue += sampleValues[i];
            }

            meanValue /= static_cast<algorithmFpType>(elementCount);

            algorithmFpType varValue = 0;
            for (size_t i = 0; i < elementCount; ++i)
            {
                varValue += (sampleValues[i] - meanValue) * (sampleValues[i] - meanValue);
            }
            if (varValue > maxVarianceValue)
            {
                maxVarianceValue = varValue;
                maxVarianceDim = j;
            }

            const_cast<NumericTable &>(x).releaseBlockOfColumnValues(columnBD);
        }
    }

    return maxVarianceDim;
}

template <typename algorithmFpType, CpuType cpu>
algorithmFpType KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    computeApproximatedMedianInParallel(size_t start, size_t end, size_t dimension, algorithmFpType upper, const NumericTable & x,
                                        const size_t * indexes, int seed, algorithmFpType * subSamples, size_t subSampleCapacity)
{
    algorithmFpType samples[__KDTREE_MEDIAN_RANDOM_SAMPLE_COUNT + 1];
    const size_t sampleCount = sizeof(samples) / sizeof(samples[0]);

    if (end - start <= sampleCount)
    {
        data_management::BlockDescriptor<algorithmFpType> sampleBD;
        for (size_t i = start; i < end; ++i)
        {
            const_cast<NumericTable &>(x).getBlockOfColumnValues(dimension, indexes[i], 1, readOnly, sampleBD);
            const algorithmFpType * const dx = sampleBD.getBlockPtr();
            samples[i - start] = *dx;
            const_cast<NumericTable &>(x).releaseBlockOfColumnValues(sampleBD);
        }
        daal::algorithms::internal::qSort<algorithmFpType, cpu>(end - start, samples);
        const algorithmFpType approximatedMedian = ((end - start) % 2 != 0) ? samples[(end - start) / 2] :
            (samples[(end - start) / 2 - 1] + samples[(end - start) / 2]) / 2.0;
        return approximatedMedian;
    }

    {
        daal::internal::BaseRNGs<cpu> brng(seed);
#ifdef KNN_INT_RANDOM_NUMBER_GENERATOR
        daal::internal::RNGs<int, cpu> rng;
        int pos;
#else
        daal::internal::RNGs<size_t, cpu> rng;
        size_t pos;
#endif
        data_management::BlockDescriptor<algorithmFpType> sampleBD;
        size_t i = 0;
        for (; i < sampleCount - 1; ++i)
        {
            rng.uniform(1, &pos, brng, start, end);
            const_cast<NumericTable &>(x).getBlockOfColumnValues(dimension, indexes[pos], 1, readOnly, sampleBD);
            const algorithmFpType * const dx = sampleBD.getBlockPtr();
            samples[i] = *dx;
            const_cast<NumericTable &>(x).releaseBlockOfColumnValues(sampleBD);
        }
        samples[i] = upper;
    }

    daal::algorithms::internal::qSort<algorithmFpType, cpu>(sampleCount, samples);

    typedef size_t Hist;
    Hist masterHist[__KDTREE_MEDIAN_RANDOM_SAMPLE_COUNT + 1] = {};

    data_management::BlockDescriptor<algorithmFpType> columnBD;
    const size_t xRowCount = x.getNumberOfRows();
    const_cast<NumericTable &>(x).getBlockOfColumnValues(dimension, 0, xRowCount, readOnly, columnBD);
    const algorithmFpType * const dx = columnBD.getBlockPtr();

    const auto rowsPerBlock = 64;
    const auto blockCount = (xRowCount + rowsPerBlock - 1) / rowsPerBlock;

    size_t subSampleCount = 0;
    for (size_t l = 0; l < sampleCount; l += __KDTREE_SEARCH_SKIP)
    {
        subSamples[subSampleCount++] = samples[l];
    }
    const size_t subSampleCount16 = subSampleCount / __SIMDWIDTH * __SIMDWIDTH;

    daal::tls<Hist *> histTLS([=]()-> Hist *
    {
        Hist * const ptr = service_scalable_calloc<Hist, cpu>(sampleCount);
        if (!ptr) { _errors->add(services::ErrorMemoryAllocationFailed); }
        return ptr;
    } );

    daal::threader_for(blockCount, blockCount, [=, &histTLS, &samples, &subSamples](int iBlock)
    {
        Hist * const hist = histTLS.local();
        if (hist)
        {
            const size_t first = start + iBlock * rowsPerBlock;
            const size_t last = min<cpu>(first + rowsPerBlock, end);

            for (size_t l = first; l < last; ++l)
            {
                const size_t bucketID = computeBucketID(samples, sampleCount, subSamples, subSampleCount, subSampleCount16, dx[indexes[l]]);
                ++hist[bucketID];
            }
        }
    } );

    histTLS.reduce([=, &masterHist](Hist * v) -> void
    {
        for (size_t j = 0; j < sampleCount; ++j)
        {
            masterHist[j] += v[j];
        }
        service_scalable_free<Hist, cpu>(v);
    } );

    const_cast<NumericTable &>(x).releaseBlockOfColumnValues(columnBD);

    size_t sumMid = 0;
    size_t i = 0;
    for (; i < sampleCount; ++i)
    {
        if (sumMid + masterHist[i] > (end - start) / 2) { break; }
        sumMid += masterHist[i];
    }

    const algorithmFpType approximatedMedian = (i + 1 < sampleCount) ? (samples[i] + samples[i + 1]) / 2 : samples[i];

    return approximatedMedian;
}

template <typename algorithmFpType, CpuType cpu>
size_t KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    computeBucketID(algorithmFpType * samples, size_t sampleCount, algorithmFpType * subSamples, size_t subSampleCount,
                    size_t subSampleCount16, algorithmFpType value)
{
#if (__CPUID__(DAAL_CPU) >= __avx__) && (__FPTYPE__(DAAL_FPTYPE) == __float__) && defined(__INTEL_COMPILER_BUILD_DATE)

    __m256 vValue = _mm256_set1_ps(value);
    size_t k = 0;
    for (; k < subSampleCount16; k += __SIMDWIDTH)
    {
        __m256 mask = _mm256_cmp_ps(_mm256_loadu_ps(subSamples + k), vValue, _CMP_GE_OS);
        int maskInt = _mm256_movemask_ps(mask);
        if (maskInt)
        {
            k = k + _bit_scan_forward(_mm256_movemask_ps(mask));
            break;
        }
    }

    if (k > subSampleCount16)
    {
        for (k = subSampleCount16; k < subSampleCount; ++k)
        {
            if (subSamples[k] >= value) { break; }
        }
    }

    size_t i = k * __KDTREE_SEARCH_SKIP;
    if (i > 0)
    {
        for (size_t j = i - __KDTREE_SEARCH_SKIP + 1; j <= i; j += __SIMDWIDTH)
        {
            __m256 vSamples = _mm256_loadu_ps(samples + j);
            __m256 mask = _mm256_cmp_ps(vSamples, vValue, _CMP_GE_OS);
            int maskInt = _mm256_movemask_ps(mask);
            if (maskInt) { return j + _bit_scan_forward(_mm256_movemask_ps(mask)); }
        }
    }

    return i;

#else // #if (__CPUID__(DAAL_CPU) >= __avx__) && (__FPTYPE__(DAAL_FPTYPE) == __float__) && defined(__INTEL_COMPILER_BUILD_DATE)

    size_t k = 0;
    for (; k < subSampleCount; ++k)
    {
        if (subSamples[k] >= value) { break; }
    }
    size_t i = k * __KDTREE_SEARCH_SKIP;
    if (i > 0)
    {
        for (size_t j = i - __KDTREE_SEARCH_SKIP + 1; j <= i; ++j)
        {
            if (samples[j] >= value) { return j; }
        }
    }
    return i;

#endif // #if (__CPUID__(DAAL_CPU) >= __avx__) && (__FPTYPE__(DAAL_FPTYPE) == __float__) && defined(__INTEL_COMPILER_BUILD_DATE)
}

template <CpuType cpu, typename ForwardIterator1, typename ForwardIterator2>
static ForwardIterator2 swapRanges(ForwardIterator1 first1, ForwardIterator1 last1, ForwardIterator2 first2)
{
    while (first1 != last1)
    {
        const auto tmp = *first1; *first1 = *first2; *first2 = tmp;

        ++first1;
        ++first2;
    }
    return first2;
}

template <CpuType cpu, typename T>
static inline void swap(T & a, T & b)
{
    const auto tmp = a;
    a = b;
    b = tmp;
}

template <typename algorithmFpType, CpuType cpu>
size_t KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    adjustIndexesInParallel(size_t start, size_t end, size_t dimension, algorithmFpType median, const NumericTable & x, size_t * indexes)
{
    const size_t xRowCount = x.getNumberOfRows();
    data_management::BlockDescriptor<algorithmFpType> columnBD;

    const_cast<NumericTable &>(x).getBlockOfColumnValues(dimension, 0, xRowCount, readOnly, columnBD);
    const algorithmFpType * const dx = columnBD.getBlockPtr();

    const auto rowsPerBlock = 128;
    const auto blockCount = (end - start + rowsPerBlock - 1) / rowsPerBlock;
    const auto idxMultiplier = 16; // For cache line separation.

    size_t * const leftSegmentStartPerBlock = static_cast<size_t *>(daal_malloc(idxMultiplier * (blockCount + 1) * sizeof(size_t)));
    size_t * const rightSegmentStartPerBlock = static_cast<size_t *>(daal_malloc(idxMultiplier * blockCount * sizeof(size_t)));

    daal::threader_for(blockCount, blockCount, [=, &leftSegmentStartPerBlock, &rightSegmentStartPerBlock](int iBlock)
    {
        const size_t first = start + iBlock * rowsPerBlock;
        const size_t last = min<cpu>(first + rowsPerBlock, end);

        size_t left = first;
        size_t right = last - 1;

        for (;;)
        {
            while ((left <= right) && (dx[indexes[left]] <= median)) { ++left; }
            while ((left < right) && (dx[indexes[right]] > median)) { --right; }
            if ((left <= right) && (dx[indexes[right]] > median))
            {
                if (right == 0) { break; }
                --right;
            }

            if (left > right) { break; }

            swap<cpu>(indexes[left], indexes[right]);
            ++left;
            --right;
        }

        leftSegmentStartPerBlock[idxMultiplier * iBlock] = first;
        rightSegmentStartPerBlock[idxMultiplier * iBlock] = left;
    } );

    leftSegmentStartPerBlock[idxMultiplier * blockCount] = end;

    // Computes median position.
    size_t idx = start;
    for (size_t i = 0; i < blockCount; ++i)
    {
        idx += rightSegmentStartPerBlock[idxMultiplier * i] - leftSegmentStartPerBlock[idxMultiplier * i];
    }

    // Swaps the segments.
    size_t leftSegment = 0;
    size_t rightSegment = blockCount - 1;
    while (leftSegment < rightSegment)
    {
        // Find the thinner segment.
        if (leftSegmentStartPerBlock[idxMultiplier * (leftSegment + 1)] - rightSegmentStartPerBlock[idxMultiplier * leftSegment] >
            rightSegmentStartPerBlock[idxMultiplier * rightSegment] - leftSegmentStartPerBlock[idxMultiplier * rightSegment])
        { // Left chunk is bigger.
            swapRanges<cpu>(&indexes[leftSegmentStartPerBlock[idxMultiplier * rightSegment]],
                            &indexes[rightSegmentStartPerBlock[idxMultiplier * rightSegment]],
                            &indexes[rightSegmentStartPerBlock[idxMultiplier * leftSegment]]);
            rightSegmentStartPerBlock[idxMultiplier * leftSegment] += rightSegmentStartPerBlock[idxMultiplier * rightSegment]
                - leftSegmentStartPerBlock[idxMultiplier * rightSegment];
            --rightSegment;
        }
        else if (leftSegmentStartPerBlock[idxMultiplier * (leftSegment + 1)] - rightSegmentStartPerBlock[idxMultiplier * leftSegment] <
            rightSegmentStartPerBlock[idxMultiplier * rightSegment] - leftSegmentStartPerBlock[idxMultiplier * rightSegment])
        { // Right chunk is bigger.
            swapRanges<cpu>(&indexes[rightSegmentStartPerBlock[idxMultiplier * leftSegment]],
                            &indexes[leftSegmentStartPerBlock[idxMultiplier * (leftSegment + 1)]],
                            &indexes[rightSegmentStartPerBlock[idxMultiplier * rightSegment]
                                     - (leftSegmentStartPerBlock[idxMultiplier * (leftSegment + 1)]
                                        - rightSegmentStartPerBlock[idxMultiplier * leftSegment])]);
            rightSegmentStartPerBlock[idxMultiplier * rightSegment] -= leftSegmentStartPerBlock[idxMultiplier * (leftSegment + 1)]
                - rightSegmentStartPerBlock[idxMultiplier * leftSegment];
            ++leftSegment;
        }
        else
        { // Both chunks are equal.
            swapRanges<cpu>(&indexes[rightSegmentStartPerBlock[idxMultiplier * leftSegment]],
                            &indexes[leftSegmentStartPerBlock[idxMultiplier * (leftSegment + 1)]],
                            &indexes[leftSegmentStartPerBlock[idxMultiplier * rightSegment]]);
            ++leftSegment;
            --rightSegment;
        }
    }

    daal_free(leftSegmentStartPerBlock);
    daal_free(rightSegmentStartPerBlock);

    const_cast<NumericTable &>(x).releaseBlockOfColumnValues(columnBD);
    return idx;
}

template <typename algorithmFpType, CpuType cpu>
void KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    copyBBox(BoundingBox<algorithmFpType> * dest, const BoundingBox<algorithmFpType> * src, size_t n)
{
    for (size_t j = 0; j < n; ++j)
    {
        dest[j] = src[j];
    }
}

template <typename algorithmFpType, CpuType cpu>
void KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    rearrangePoints(NumericTable & x, const size_t * indexes)
{
    const size_t xRowCount = x.getNumberOfRows();
    const size_t xColumnCount = x.getNumberOfColumns();
    const auto maxThreads = threader_get_threads_number();

    algorithmFpType * buffer = nullptr;

    data_management::BlockDescriptor<algorithmFpType> columnReadBD, columnWriteBD;

    for (size_t i = 0; i < xColumnCount; ++i)
    {
        x.getBlockOfColumnValues(i, 0, xRowCount, readOnly, columnReadBD);
        x.getBlockOfColumnValues(i, 0, xRowCount, writeOnly, columnWriteBD);
        const algorithmFpType * const rx = columnReadBD.getBlockPtr();
        algorithmFpType * const wx = columnWriteBD.getBlockPtr();
        algorithmFpType * const awx = (rx != wx) ? wx :
            (buffer ? buffer : (buffer = static_cast<algorithmFpType *>(daal_malloc(xRowCount * sizeof(algorithmFpType)))));
        if (!awx)
        {
            _errors->add(services::ErrorMemoryAllocationFailed);
            x.releaseBlockOfColumnValues(columnReadBD);
            x.releaseBlockOfColumnValues(columnWriteBD);
            break;
        }

        const auto rowsPerBlock = 256;
        const auto blockCount = (xRowCount + rowsPerBlock - 1) / rowsPerBlock;

        daal::threader_for(blockCount, blockCount, [=](int iBlock)
        {
            const size_t first = iBlock * rowsPerBlock;
            const size_t last = min<cpu>(static_cast<decltype(xRowCount)>(first + rowsPerBlock), xRowCount);

            size_t j = first;
            if (last > 4)
            {
                const size_t lastMinus4 = last - 4;
                for (; j < lastMinus4; ++j)
                {
                    DAAL_PREFETCH_READ_T0(&rx[indexes[j + 4]]);
                    awx[j] = rx[indexes[j]];
                }
            }
            for (; j < last; ++j)
            {
                awx[j] = rx[indexes[j]];
            }
        } );

        if (rx == wx)
        {
            daal::threader_for(blockCount, blockCount, [=](int iBlock)
            {
                const size_t first = iBlock * rowsPerBlock;
                const size_t last = min<cpu>(static_cast<decltype(xRowCount)>(first + rowsPerBlock), xRowCount);

                auto j = first;
                if (last > 4)
                {
                    const size_t lastMinus4 = last - 4;
                    for (; j < lastMinus4; ++j)
                    {
                        DAAL_PREFETCH_READ_T0(&awx[j + 4]);
                        wx[j] = awx[j];
                    }
                }
                for (; j < last; ++j)
                {
                    wx[j] = awx[j];
                }
            } );
        }

        x.releaseBlockOfColumnValues(columnReadBD);
        x.releaseBlockOfColumnValues(columnWriteBD);
    }

    daal_free(buffer);
}

template <typename algorithmFpType, CpuType cpu>
void KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    buildSecondPartOfKDTree(Queue<BuildNode, cpu> & q, BoundingBox<algorithmFpType> * & bboxQ, const NumericTable & x,
                            kdtree_knn_classification::Model & r, size_t * indexes, int seed)
{
    typedef daal::internal::Math<algorithmFpType, cpu> Math;
    typedef BoundingBox<algorithmFpType> BBox;
    typedef IndexValuePair<algorithmFpType, cpu> IdxValue;

    if (q.size() == 0)
    {
        return;
    }

    const size_t xRowCount = x.getNumberOfRows();
    const size_t xColumnCount = x.getNumberOfColumns();

    const algorithmFpType base = 2.0;
    const size_t expectedMaxDepth = (Math::sLog(xRowCount) / Math::sLog(base) + 1) * __KDTREE_DEPTH_MULTIPLICATION_FACTOR;
    const size_t stackSize = Math::sPowx(base, Math::sCeil(Math::sLog(expectedMaxDepth) / Math::sLog(base))) * 64;

    BuildNode * const bnQ = static_cast<BuildNode *>(daal_malloc(q.size() * sizeof(BuildNode)));
    size_t posQ = 0;
    while (q.size() > 0)
    {
        bnQ[posQ++] = q.pop();
    }

    services::Atomic<size_t> threadIndex(0);
    struct Local
    {
        Stack<BuildNode, cpu> buildStack;
        BBox * bboxes;
        size_t bboxPos;
        size_t nodeIndex;
        size_t threadIndex;
        IdxValue * inSortValues;
        IdxValue * outSortValues;

        Local() : buildStack(), bboxes(nullptr), bboxPos(0), nodeIndex(0), threadIndex(0), inSortValues(nullptr), outSortValues(nullptr) {}
    };

    const auto maxThreads = threader_get_threads_number();

    services::SharedPtr<KDTreeTable> kdTreeTablePtr = r.impl()->getKDTreeTable();
    KDTreeTable & kdTreeTable = *kdTreeTablePtr;

    const auto rowsPerBlock = (posQ + maxThreads - 1) / maxThreads;
    const auto blockCount = (posQ + rowsPerBlock - 1) / rowsPerBlock;

    const size_t lastNodeIndex = r.impl()->getLastNodeIndex();
    const size_t maxNodeCount = kdTreeTable.getNumberOfRows();
    const size_t emptyNodeCount = maxNodeCount - lastNodeIndex;
    const size_t segment = (emptyNodeCount + maxThreads - 1) / maxThreads;
    size_t * const firstNodeIndex = static_cast<size_t *>(daal_malloc((maxThreads + 1) * sizeof(*firstNodeIndex)));
    size_t nodeIndex = lastNodeIndex;
    for (size_t i = 0; i < maxThreads; ++i)
    {
        firstNodeIndex[i] = nodeIndex;
        nodeIndex += segment;
    }
    firstNodeIndex[maxThreads] = maxNodeCount;

    daal::tls<Local *> localTLS([=, &threadIndex, &firstNodeIndex, &stackSize]()-> Local *
    {
        Local * const ptr = service_scalable_calloc<Local, cpu>(1);
        if (ptr)
        {
            if (!(
                  ((ptr->bboxes = service_scalable_calloc<BBox, cpu>(stackSize * xColumnCount)) != nullptr) &&
                  ((ptr->inSortValues = service_scalable_calloc<IdxValue, cpu>(__KDTREE_INDEX_VALUE_PAIRS_PER_THREAD)) != nullptr) &&
                  ((ptr->outSortValues = service_scalable_calloc<IdxValue, cpu>(__KDTREE_INDEX_VALUE_PAIRS_PER_THREAD)) != nullptr) &&
                  ptr->buildStack.init(stackSize)))
            {
                _errors->add(services::ErrorMemoryAllocationFailed);
                service_scalable_free<IdxValue, cpu>(ptr->outSortValues);
                service_scalable_free<IdxValue, cpu>(ptr->inSortValues);
                service_scalable_free<BBox, cpu>(ptr->bboxes);
                service_scalable_free<Local, cpu>(ptr);
                return nullptr;
            }
            ptr->bboxPos = 0;
            ptr->threadIndex = threadIndex.inc() - 1;
            ptr->nodeIndex = firstNodeIndex[ptr->threadIndex];
        }
        else { _errors->add(services::ErrorMemoryAllocationFailed); }
        return ptr;
    } );

    daal::threader_for(blockCount, blockCount, [=, &localTLS, &firstNodeIndex, &kdTreeTable, &x, &r, &rowsPerBlock, &xColumnCount](int iBlock)
    {
        Local * const local = localTLS.local();
        if (local)
        {
            const size_t first = iBlock * rowsPerBlock;
            const size_t last = min<cpu>(first + rowsPerBlock, posQ);

            BuildNode bn, bnLeft, bnRight;
            BBox * bboxCur = nullptr, * bboxLeft = nullptr, * bboxRight = nullptr;
            KDTreeNode * curNode = nullptr;
            algorithmFpType lowerD, upperD;

            size_t sophisticatedSampleIndexes[__KDTREE_DIMENSION_SELECTION_SIZE];
            algorithmFpType sophisticatedSampleValues[__KDTREE_DIMENSION_SELECTION_SIZE];

            for (size_t i = first; i < last; ++i)
            {
                bn = bnQ[i];
                bboxCur = &bboxQ[bn.queueOrStackPos * xColumnCount];
                local->buildStack.push(bn);
                copyBBox(&(local->bboxes[local->bboxPos * xColumnCount]), bboxCur, xColumnCount);
                ++local->bboxPos;

                while (local->buildStack.size() > 0)
                {
                    bn = local->buildStack.pop();
                    --local->bboxPos;
                    bboxCur = &(local->bboxes[local->bboxPos * xColumnCount]);
                    curNode = static_cast<KDTreeNode *>(kdTreeTable.getArray()) + bn.nodePos;

                    if (bn.end - bn.start <= __KDTREE_LEAF_BUCKET_SIZE)
                    { // Should be leaf node.
                        curNode->cutPoint = 0;
                        curNode->dimension = __KDTREE_NULLDIMENSION;
                        curNode->leftIndex = bn.start;
                        curNode->rightIndex = bn.end;
                    }
                    else // if (bn.end - bn.start <= __KDTREE_LEAF_BUCKET_SIZE)
                    {
                        const auto d = selectDimensionSophisticated(bn.start, bn.end, sophisticatedSampleIndexes, sophisticatedSampleValues,
                                                                    __KDTREE_DIMENSION_SELECTION_SIZE, x, indexes, seed);
                        lowerD = bboxCur[d].lower;
                        upperD = bboxCur[d].upper;
                        const algorithmFpType approximatedMedian = computeApproximatedMedianInSerial(bn.start, bn.end, d, bboxCur[d].upper,
                                                                                                     local->inSortValues, local->outSortValues,
                                                                                                     __KDTREE_INDEX_VALUE_PAIRS_PER_THREAD, x,
                                                                                                     indexes, seed);
                        const auto idx = adjustIndexesInSerial(bn.start, bn.end, d, approximatedMedian, x, indexes);

                        curNode->cutPoint = approximatedMedian;
                        curNode->dimension = d;
                        curNode->leftIndex = (local->nodeIndex)++;
                        curNode->rightIndex = (local->nodeIndex)++;

                        if (local->nodeIndex >= firstNodeIndex[local->threadIndex + 1])
                        {
                            // Node count per thread is not enough - it is required to increase sample count for better balance.
                            _errors->add(services::ErrorIncorrectSizeOfArray);
                            return;
                        }
                        if (local->bboxPos + 2 >= stackSize)
                        {
                            // internal stack overflow.
                            _errors->add(services::ErrorIncorrectSizeOfArray);
                            return;
                        }

                        // Right first to give lower node index for left.
                        bnRight.start = idx;
                        bnRight.end = bn.end;
                        bnRight.nodePos = curNode->rightIndex;
                        bnRight.queueOrStackPos = local->bboxPos;
                        ++local->bboxPos;
                        bboxRight = &local->bboxes[bnRight.queueOrStackPos * xColumnCount];
                        copyBBox(bboxRight, bboxCur, xColumnCount);
                        bboxRight[d].lower = approximatedMedian;
                        bboxRight[d].upper = upperD;
                        local->buildStack.push(bnRight);
                        bnLeft.start = bn.start;
                        bnLeft.end = idx;
                        bnLeft.nodePos = curNode->leftIndex;
                        bnLeft.queueOrStackPos = local->bboxPos;
                        ++local->bboxPos;
                        bboxLeft = &local->bboxes[bnLeft.queueOrStackPos * xColumnCount];
                        copyBBox(bboxLeft, bboxCur, xColumnCount);
                        bboxLeft[d].lower = lowerD;
                        bboxLeft[d].upper = upperD;
                        local->buildStack.push(bnLeft);
                    } // if (bn.end - bn.start <= __KDTREE_LEAF_BUCKET_SIZE)
                } // while (local->buildStack.size() > 0)
            } // for (auto i = first; i < last; ++i)
        } // if (local)
    } );

    localTLS.reduce([=](Local * ptr) -> void
    {
        if (ptr)
        {
            service_scalable_free<IdxValue, cpu>(ptr->inSortValues);
            service_scalable_free<IdxValue, cpu>(ptr->outSortValues);
            service_scalable_free<BBox, cpu>(ptr->bboxes);
            ptr->buildStack.clear();
            service_scalable_free<Local, cpu>(ptr);
        }
    } );

    daal_free(firstNodeIndex);
    daal_free(bnQ);
}

template <typename algorithmFpType, CpuType cpu>
algorithmFpType KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    computeApproximatedMedianInSerial(size_t start, size_t end, size_t dimension, algorithmFpType upper,
                                      IndexValuePair<algorithmFpType, cpu> * inSortValues, IndexValuePair<algorithmFpType, cpu> * outSortValues,
                                      size_t sortValueCount, const NumericTable & x, size_t * indexes, int seed)
{
    size_t i, j;
    const auto xRowCount = x.getNumberOfRows();
    data_management::BlockDescriptor<algorithmFpType> columnBD;
    const_cast<NumericTable &>(x).getBlockOfColumnValues(dimension, 0, xRowCount, readOnly, columnBD);
    const algorithmFpType * const dx = columnBD.getBlockPtr();
    if (end - start < sortValueCount)
    {
        const size_t elementCount = end - start;
        i = 0;
        if (elementCount > 16)
        {
            const size_t elementCountMinus16 = elementCount - 16;
            for (; i < elementCountMinus16; ++i)
            {
                DAAL_PREFETCH_READ_T0(dx + indexes[start + i + 16]);
                inSortValues[i].value = dx[indexes[start + i]];
                inSortValues[i].idx = indexes[start + i];
            }
        }
        for (; i < elementCount; ++i)
        {
            inSortValues[i].value = dx[indexes[start + i]];
            inSortValues[i].idx = indexes[start + i];
        }

        radixSort(inSortValues, elementCount, outSortValues);

        // Copy back the indexes.
        for (i = 0; i < elementCount; ++i)
        {
            indexes[start + i] = inSortValues[i].idx;
        }

        const algorithmFpType approximatedMedian = ((end - start) % 2 != 0) ? dx[indexes[start + (end - start) / 2]] :
            (dx[indexes[start + (end - start) / 2 - 1]] + dx[indexes[start + (end - start) / 2]]) / 2.0;

        const_cast<NumericTable &>(x).releaseBlockOfColumnValues(columnBD);

        return approximatedMedian;
    } // if (end - start < sortValueCount)

    size_t sampleCount = min<cpu>(static_cast<size_t>(static_cast<algorithmFpType>(end - start) * __KDTREE_SAMPLES_PERCENT / 100),
                                  static_cast<size_t>(__KDTREE_MAX_SAMPLES + 1));

    if (sampleCount < __KDTREE_MIN_SAMPLES) { sampleCount = __KDTREE_MIN_SAMPLES + 1; }

    algorithmFpType * const samples = static_cast<algorithmFpType *>(daal_malloc(sampleCount * sizeof(*samples)));

    daal::internal::BaseRNGs<cpu> brng(seed);
#ifdef KNN_INT_RANDOM_NUMBER_GENERATOR
    daal::internal::RNGs<int, cpu> rng;
    int pos;
#else
    daal::internal::RNGs<size_t, cpu> rng;
    size_t pos;
#endif
    for (i = 0; i < sampleCount - 1; ++i)
    {
        rng.uniform(1, &pos, brng, start, end);
        samples[i] = dx[indexes[pos]];
    }

    samples[i] = upper;
    daal::algorithms::internal::qSort<algorithmFpType, cpu>(sampleCount, samples);

    size_t * const hist = static_cast<size_t *>(daal_malloc(sampleCount * sizeof(*hist)));
    for (i = 0; i <sampleCount; ++i)
    {
        hist[i] = 0;
    }

    size_t subSampleCount = (end - start) / __KDTREE_SEARCH_SKIP + 1;
    algorithmFpType * const subSamples = static_cast<algorithmFpType *>(daal_malloc(subSampleCount * sizeof(*subSamples)));
    size_t subSamplesPos = 0;
    for (size_t l = 0; l < sampleCount; l += __KDTREE_SEARCH_SKIP)
    {
        subSamples[subSamplesPos++] = samples[l];
    }
    subSampleCount = subSamplesPos;
    const size_t subSampleCount16 = subSampleCount / __SIMDWIDTH * __SIMDWIDTH;
    size_t l = start;
    if (end > 2)
    {
        const size_t endMinus2 = end - 2;
        for (; l < endMinus2; ++l)
        {
            DAAL_PREFETCH_READ_T0(&dx[indexes[l + 2]]);
            const auto bucketID = computeBucketID(samples, sampleCount, subSamples, subSampleCount, subSampleCount16, dx[indexes[l]]);
            ++hist[bucketID];
        }
    }
    for (; l < end; ++l)
    {
        const auto bucketID = computeBucketID(samples, sampleCount, subSamples, subSampleCount, subSampleCount16, dx[indexes[l]]);
        ++hist[bucketID];
    }

    size_t sumMid = 0;
    for (i = 0; i < sampleCount; ++i)
    {
        if (sumMid + hist[i] > (end - start) / 2) { break; }
        sumMid += hist[i];
    }

    const algorithmFpType approximatedMedian = (i + 1 < sampleCount) ? (samples[i] + samples[i + 1]) / 2 : samples[i];

    const_cast<NumericTable &>(x).releaseBlockOfColumnValues(columnBD);

    daal_free(samples);
    daal_free(hist);
    daal_free(subSamples);

    return approximatedMedian;
}

template <typename algorithmFpType, CpuType cpu>
size_t KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    adjustIndexesInSerial(size_t start, size_t end, size_t dimension, algorithmFpType median, const NumericTable & x, size_t * indexes)
{
    const size_t xRowCount = x.getNumberOfRows();
    data_management::BlockDescriptor<algorithmFpType> columnBD;
    const_cast<NumericTable &>(x).getBlockOfColumnValues(dimension, 0, xRowCount, readOnly, columnBD);
    const algorithmFpType * const dx = columnBD.getBlockPtr();

    size_t left = start;
    size_t right = end - 1;
    for (;;)
    {
        while ((left <= right) && (dx[indexes[left]] < median)) { ++left; }
        while ((left < right) && (dx[indexes[right]] >= median)) { --right; }
        if ((left <= right) && (dx[indexes[right]] >= median))
        {
            if (right == 0) { break; }
            --right;
        }

        if (left > right) { break; }

        swap<cpu>(indexes[left], indexes[right]);
        ++left;
        --right;
    }

    const size_t lim1 = left;
    right = end - 1;
    for (;;)
    {
        while ((left <= right) && (dx[indexes[left]] <= median)) { ++left; }
        while ((left < right) && (dx[indexes[right]] > median)) { --right; }
        if ((left <= right) && (dx[indexes[right]] > median))
        {
            if (right == 0) { break; }
            --right;
        }

        if (left > right) { break; }

        swap<cpu>(indexes[left], indexes[right]);
        ++left;
        --right;
    }

    const size_t lim2 = left;
    const size_t idx = (lim1 > start + (end - start) / 2) ? lim1 : (lim2 < start + (end - start) / 2) ? lim2 : start + (end - start) / 2;

    const_cast<NumericTable &>(x).releaseBlockOfColumnValues(columnBD);

    return idx;
}

template <typename algorithmFpType, CpuType cpu>
void KNNClassificationTrainBatchKernel<algorithmFpType, training::defaultDense, cpu>::
    radixSort(IndexValuePair<algorithmFpType, cpu> * inValues, size_t valueCount, IndexValuePair<algorithmFpType, cpu> * outValues)
{
#if (__FPTYPE__(DAAL_FPTYPE) == __float__)
    typedef IndexValuePair<algorithmFpType, cpu> Item;
    typedef unsigned int IntegerType;
    const size_t histogramSize = 256;
    int histogram[histogramSize], histogramPS[histogramSize + 1];
    Item * first = inValues;
    Item * second = outValues;
    size_t valueCount4 = valueCount / 4 * 4;
    for (unsigned int pass = 0; pass < 3; ++pass)
    {
        for (size_t i = 0; i < histogramSize; ++i) { histogram[i] = 0; }
        for (size_t i = 0; i < valueCount4; i += 4)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            IntegerType val2 = *reinterpret_cast<IntegerType *>(&first[i + 1].value);
            IntegerType val3 = *reinterpret_cast<IntegerType *>(&first[i + 2].value);
            IntegerType val4 = *reinterpret_cast<IntegerType *>(&first[i + 3].value);
            ++histogram[(val1 >> (pass * 8)) & 0xFF];
            ++histogram[(val2 >> (pass * 8)) & 0xFF];
            ++histogram[(val3 >> (pass * 8)) & 0xFF];
            ++histogram[(val4 >> (pass * 8)) & 0xFF];
        }
        for (size_t i = valueCount4; i < valueCount; ++i)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            ++histogram[(val1 >> (pass * 8)) & 0xFF];
        }

        int sum = 0, prevSum = 0;
        for (size_t i = 0; i < histogramSize; ++i)
        {
            sum += histogram[i];
            histogramPS[i] = prevSum;
            prevSum = sum;
        }
        histogramPS[histogramSize] = prevSum;

        for (size_t i = 0; i < valueCount; ++i)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            const int pos = histogramPS[(val1 >> (pass * 8)) & 0xFF]++;
            second[pos] = first[i];
        }

        Item * temp = first;
        first = second;
        second = temp;
    }
    {
        unsigned int pass = 3;
        for (size_t i = 0; i < histogramSize; ++i) { histogram[i] = 0; }
        for (size_t i = 0; i < valueCount4; i += 4)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            IntegerType val2 = *reinterpret_cast<IntegerType *>(&first[i + 1].value);
            IntegerType val3 = *reinterpret_cast<IntegerType *>(&first[i + 2].value);
            IntegerType val4 = *reinterpret_cast<IntegerType *>(&first[i + 3].value);
            ++histogram[(val1 >> (pass * 8)) & 0xFF];
            ++histogram[(val2 >> (pass * 8)) & 0xFF];
            ++histogram[(val3 >> (pass * 8)) & 0xFF];
            ++histogram[(val4 >> (pass * 8)) & 0xFF];
        }
        for (size_t i = valueCount4; i < valueCount; ++i)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            ++histogram[(val1 >> (pass * 8)) & 0xFF];
        }

        int sum = 0, prevSum = 0;
        for (size_t i = 0; i < histogramSize; ++i)
        {
            sum += histogram[i];
            histogramPS[i] = prevSum;
            prevSum = sum;
        }
        histogramPS[histogramSize] = prevSum;

        // Handle negative values.
        const size_t indexOfNegatives = histogramSize / 2;
        int countOfNegatives = histogramPS[histogramSize] - histogramPS[indexOfNegatives];
        // Fixes offsets for positive values.
        for (size_t i = 0; i < indexOfNegatives - 1; ++i)
        {
            histogramPS[i] += countOfNegatives;
        }
        // Fixes offsets for negative values.
        histogramPS[histogramSize - 1] = histogram[histogramSize - 1];
        for (size_t i = 0; i < indexOfNegatives - 1; ++i)
        {
            histogramPS[histogramSize - 2 - i] = histogramPS[histogramSize - 1 - i] + histogram[histogramSize - 2 - i];
        }

        for (size_t i = 0; i < valueCount; ++i)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            const int bin = (val1 >> (pass * 8)) & 0xFF;
            int pos;
            if (bin >= indexOfNegatives) { pos = --histogramPS[bin]; }
            else { pos = histogramPS[bin]++; }
            second[pos] = first[i];
        }
    }
#else // #if (__FPTYPE__(DAAL_FPTYPE) == __float__)
    typedef IndexValuePair<algorithmFpType, cpu> Item;
    typedef DAAL_UINT64 IntegerType;
    const size_t histogramSize = 256;
    int histogram[histogramSize], histogramPS[histogramSize + 1];
    Item * first = inValues;
    Item * second = outValues;
    size_t valueCount4 = valueCount / 4 * 4;
    for (unsigned int pass = 0; pass < 7; ++pass)
    {
        for (size_t i = 0; i < histogramSize; ++i) { histogram[i] = 0; }
        for (size_t i = 0; i < valueCount4; i += 4)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            IntegerType val2 = *reinterpret_cast<IntegerType *>(&first[i + 1].value);
            IntegerType val3 = *reinterpret_cast<IntegerType *>(&first[i + 2].value);
            IntegerType val4 = *reinterpret_cast<IntegerType *>(&first[i + 3].value);
            ++histogram[(val1 >> (pass * 8)) & 0xFF];
            ++histogram[(val2 >> (pass * 8)) & 0xFF];
            ++histogram[(val3 >> (pass * 8)) & 0xFF];
            ++histogram[(val4 >> (pass * 8)) & 0xFF];
        }
        for (size_t i = valueCount4; i < valueCount; ++i)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            ++histogram[(val1 >> (pass * 8)) & 0xFF];
        }

        int sum = 0, prevSum = 0;
        for (size_t i = 0; i < histogramSize; ++i)
        {
            sum += histogram[i];
            histogramPS[i] = prevSum;
            prevSum = sum;
        }
        histogramPS[histogramSize] = prevSum;

        for (size_t i = 0; i < valueCount; ++i)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            const int pos = histogramPS[(val1 >> (pass * 8)) & 0xFF]++;
            second[pos] = first[i];
        }

        Item * temp = first;
        first = second;
        second = temp;
    }
    {
        unsigned int pass = 7;
        for (size_t i = 0; i < histogramSize; ++i) { histogram[i] = 0; }
        for (size_t i = 0; i < valueCount4; i += 4)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            IntegerType val2 = *reinterpret_cast<IntegerType *>(&first[i + 1].value);
            IntegerType val3 = *reinterpret_cast<IntegerType *>(&first[i + 2].value);
            IntegerType val4 = *reinterpret_cast<IntegerType *>(&first[i + 3].value);
            ++histogram[(val1 >> (pass * 8)) & 0xFF];
            ++histogram[(val2 >> (pass * 8)) & 0xFF];
            ++histogram[(val3 >> (pass * 8)) & 0xFF];
            ++histogram[(val4 >> (pass * 8)) & 0xFF];
        }
        for (size_t i = valueCount4; i < valueCount; ++i)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            ++histogram[(val1 >> (pass * 8)) & 0xFF];
        }

        int sum = 0, prevSum = 0;
        for (size_t i = 0; i < histogramSize; ++i)
        {
            sum += histogram[i];
            histogramPS[i] = prevSum;
            prevSum = sum;
        }
        histogramPS[histogramSize] = prevSum;

        // Handle negative values.
        const size_t indexOfNegatives = histogramSize / 2;
        int countOfNegatives = histogramPS[histogramSize] - histogramPS[indexOfNegatives];
        // Fixes offsets for positive values.
        for (size_t i = 0; i < indexOfNegatives - 1; ++i)
        {
            histogramPS[i] += countOfNegatives;
        }
        // Fixes offsets for negative values.
        histogramPS[histogramSize - 1] = histogram[histogramSize - 1];
        for (size_t i = 0; i < indexOfNegatives - 1; ++i)
        {
            histogramPS[histogramSize - 2 - i] = histogramPS[histogramSize - 1 - i] + histogram[histogramSize - 2 - i];
        }

        for (size_t i = 0; i < valueCount; ++i)
        {
            IntegerType val1 = *reinterpret_cast<IntegerType *>(&first[i].value);
            const int bin = (val1 >> (pass * 8)) & 0xFF;
            int pos;
            if (bin >= indexOfNegatives) { pos = --histogramPS[bin]; }
            else { pos = histogramPS[bin]++; }
            second[pos] = first[i];
        }
    }
#endif // #if (__FPTYPE__(DAAL_FPTYPE) == __float__)
}

} // namespace internal
} // namespace training
} // namespace kdtree_knn_classification
} // namespace algorithms
} // namespace daal

#endif
