# =============================================================================
# NorthBridge Bank — Customer 360 & Risk Analytics Dashboard
# Streamlit in Snowflake (SiS)
# =============================================================================

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from snowflake.snowpark.context import get_active_session

DB = "CUST360_NORTHBRIDGE_DATABASE"
GOLD = f"{DB}.GOLD"

st.set_page_config(
    page_title="NorthBridge Bank | Customer 360",
    page_icon="🏦",
    layout="wide",
)

session = get_active_session()


@st.cache_data(ttl=300)
def run_query(sql: str) -> pd.DataFrame:
    return session.sql(sql).to_pandas()


def safe_num(val, default=0):
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return default
    try:
        return float(val)
    except (TypeError, ValueError):
        return default


def safe_int(val, default=0):
    return int(safe_num(val, default))


# ── Sidebar filters ───────────────────────────────────────────
with st.sidebar:
    st.title("🏦 NorthBridge Bank")
    st.caption("Customer 360 & Risk Analytics")
    st.divider()

    segments = run_query(
        f"SELECT DISTINCT CUSTOMER_SEGMENT FROM {GOLD}.CUST360_DIM_CUSTOMER ORDER BY 1"
    )
    selected_segments = st.multiselect(
        "Customer Segment",
        options=segments["CUSTOMER_SEGMENT"].tolist(),
        default=segments["CUSTOMER_SEGMENT"].tolist(),
    )

    selected_risks = st.multiselect(
        "Risk Rating",
        options=["Low", "Medium", "High"],
        default=["Low", "Medium", "High"],
    )

    regions = run_query(
        f"SELECT DISTINCT REGION FROM {GOLD}.CUST360_DIM_BRANCH ORDER BY 1"
    )
    selected_regions = st.multiselect(
        "Region",
        options=regions["REGION"].tolist(),
        default=regions["REGION"].tolist(),
    )

    st.divider()
    st.caption("Cache TTL: 5 minutes")


def in_clause(values):
    return "','".join(values)


seg_filter = in_clause(selected_segments)
risk_filter = in_clause(selected_risks)
reg_filter = in_clause(selected_regions)

st.title("🏦 NorthBridge Bank — Customer 360 Dashboard")
st.caption(
    "Enterprise risk analytics and portfolio performance across all business lines."
)
st.divider()

tab1, tab2, tab3, tab4, tab5 = st.tabs(
    [
        "📊 Executive KPIs",
        "👥 Customer Insights",
        "💳 Loan Portfolio",
        "💸 Transactions",
        "🔍 Risk & Compliance",
    ]
)


# ═════════════════════════════════════════════════════════════
# TAB 1 — EXECUTIVE KPIs
# ═════════════════════════════════════════════════════════════
with tab1:
    st.subheader("Executive Summary")

    kpi = run_query(
        f"""
        SELECT
            COUNT(DISTINCT c.CUSTOMER_ID)                               AS TOTAL_CUSTOMERS,
            COALESCE(SUM(a.CURRENT_BALANCE), 0)                         AS TOTAL_AUM,
            COUNT(DISTINCT l.LOAN_ID)                                   AS TOTAL_LOANS,
            COALESCE(SUM(l.LOAN_AMOUNT), 0)                             AS TOTAL_LOAN_BOOK,
            COALESCE(SUM(l.OUTSTANDING_BALANCE), 0)                     AS TOTAL_OUTSTANDING,
            ROUND(AVG(c.CREDIT_SCORE), 1)                               AS AVG_CREDIT_SCORE,
            COALESCE(ROUND(
                SUM(CASE WHEN l.LOAN_STATUS IN ('Defaulted','Delinquent')
                    THEN l.LOAN_AMOUNT ELSE 0 END)
                / NULLIF(SUM(l.LOAN_AMOUNT), 0) * 100, 2), 0)          AS NPL_RATIO_PCT,
            COUNT(DISTINCT CASE WHEN t.STATUS = 'Completed'
                THEN t.TRANSACTION_ID END)                              AS COMPLETED_TXNS,
            COALESCE(SUM(CASE WHEN t.STATUS = 'Completed' THEN t.AMOUNT ELSE 0 END), 0) AS TOTAL_TXN_VOLUME
        FROM {GOLD}.CUST360_DIM_CUSTOMER c
        LEFT JOIN {GOLD}.CUST360_FACT_ACCOUNT_BALANCES a  ON c.CUSTOMER_ID = a.CUSTOMER_ID
        LEFT JOIN {GOLD}.CUST360_FACT_LOANS l             ON c.CUSTOMER_ID = l.CUSTOMER_ID
        LEFT JOIN {GOLD}.CUST360_FACT_TRANSACTIONS t      ON c.CUSTOMER_ID = t.CUSTOMER_ID
        WHERE c.CUSTOMER_SEGMENT IN ('{seg_filter}')
          AND c.RISK_RATING       IN ('{risk_filter}')
    """
    )
    k = kpi.iloc[0]

    col1, col2, col3, col4, col5 = st.columns(5)
    col1.metric("Total Customers", f"{safe_int(k['TOTAL_CUSTOMERS']):,}")
    col2.metric("Total AUM", f"${safe_num(k['TOTAL_AUM']):,.0f}")
    col3.metric("Total Loan Book", f"${safe_num(k['TOTAL_LOAN_BOOK']):,.0f}")
    col4.metric("Avg Credit Score", f"{safe_num(k['AVG_CREDIT_SCORE']):.0f}")
    col5.metric("NPL Ratio", f"{safe_num(k['NPL_RATIO_PCT']):.1f}%")

    st.divider()

    seg_df = run_query(
        f"""
        SELECT
            c.CUSTOMER_SEGMENT,
            COUNT(DISTINCT c.CUSTOMER_ID)        AS CUSTOMER_COUNT,
            ROUND(AVG(c.ANNUAL_INCOME), 2)       AS AVG_INCOME,
            ROUND(AVG(c.CREDIT_SCORE), 1)        AS AVG_CREDIT_SCORE,
            COALESCE(SUM(a.CURRENT_BALANCE), 0)  AS TOTAL_BALANCE,
            COUNT(DISTINCT l.LOAN_ID)            AS LOAN_COUNT,
            COALESCE(SUM(l.LOAN_AMOUNT), 0)      AS TOTAL_LOANS
        FROM {GOLD}.CUST360_DIM_CUSTOMER c
        LEFT JOIN {GOLD}.CUST360_FACT_ACCOUNT_BALANCES a ON c.CUSTOMER_ID = a.CUSTOMER_ID
        LEFT JOIN {GOLD}.CUST360_FACT_LOANS l            ON c.CUSTOMER_ID = l.CUSTOMER_ID
        WHERE c.CUSTOMER_SEGMENT IN ('{seg_filter}')
        GROUP BY 1
        ORDER BY TOTAL_BALANCE DESC NULLS LAST
    """
    )

    col_a, col_b = st.columns(2)
    with col_a:
        if not seg_df.empty:
            fig = px.bar(
                seg_df,
                x="CUSTOMER_SEGMENT",
                y="TOTAL_BALANCE",
                color="CUSTOMER_SEGMENT",
                text_auto=".2s",
                title="Total AUM by Customer Segment",
                labels={
                    "TOTAL_BALANCE": "Balance (USD)",
                    "CUSTOMER_SEGMENT": "Segment",
                },
            )
            fig.update_layout(showlegend=False)
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("No data for selected filters.")

    with col_b:
        if not seg_df.empty:
            fig = px.scatter(
                seg_df,
                x="AVG_INCOME",
                y="AVG_CREDIT_SCORE",
                size="CUSTOMER_COUNT",
                color="CUSTOMER_SEGMENT",
                title="Income vs Credit Score by Segment",
                labels={
                    "AVG_INCOME": "Avg Annual Income",
                    "AVG_CREDIT_SCORE": "Avg Credit Score",
                },
                size_max=60,
            )
            st.plotly_chart(fig, use_container_width=True)

    reg_df = run_query(
        f"""
        SELECT
            b.REGION                              AS BRANCH_REGION,
            b.STATE                               AS BRANCH_STATE,
            COUNT(DISTINCT c.CUSTOMER_ID)         AS CUSTOMERS,
            ROUND(AVG(c.CREDIT_SCORE), 1)         AS AVG_CREDIT_SCORE,
            COALESCE(SUM(a.CURRENT_BALANCE), 0)   AS TOTAL_AUM
        FROM {GOLD}.CUST360_DIM_BRANCH b
        LEFT JOIN {GOLD}.CUST360_DIM_CUSTOMER c           ON b.BRANCH_ID = c.PRIMARY_BRANCH_ID
        LEFT JOIN {GOLD}.CUST360_FACT_ACCOUNT_BALANCES a  ON c.CUSTOMER_ID = a.CUSTOMER_ID
        WHERE b.REGION IN ('{reg_filter}')
        GROUP BY 1, 2
        ORDER BY TOTAL_AUM DESC NULLS LAST
    """
    )

    if not reg_df.empty and reg_df["TOTAL_AUM"].sum() > 0:
        fig = px.treemap(
            reg_df,
            path=["BRANCH_REGION", "BRANCH_STATE"],
            values="TOTAL_AUM",
            color="AVG_CREDIT_SCORE",
            color_continuous_scale="RdYlGn",
            title="AUM Treemap — Region → State (colour = Avg Credit Score)",
        )
        st.plotly_chart(fig, use_container_width=True)


# ═════════════════════════════════════════════════════════════
# TAB 2 — CUSTOMER INSIGHTS
# ═════════════════════════════════════════════════════════════
with tab2:
    st.subheader("Customer Segmentation & Demographics")

    cust_df = run_query(
        f"""
        SELECT
            CUSTOMER_ID, FULL_NAME, CUSTOMER_SEGMENT, CUSTOMER_TIER,
            ANNUAL_INCOME, CREDIT_SCORE, RISK_RATING, KYC_STATUS,
            EMPLOYMENT_STATUS, GENDER, MARITAL_STATUS,
            ADDRESS_CITY AS CITY, ADDRESS_STATE AS STATE,
            PRIMARY_BRANCH_ID AS BRANCH_ID,
            CASE
                WHEN ANNUAL_INCOME < 40000  THEN 'Low (<40K)'
                WHEN ANNUAL_INCOME < 80000  THEN 'Middle (40K-80K)'
                WHEN ANNUAL_INCOME < 150000 THEN 'Upper-Middle (80K-150K)'
                ELSE 'High (>150K)'
            END AS INCOME_TIER,
            CASE
                WHEN CREDIT_SCORE >= 750 THEN 'Excellent (750+)'
                WHEN CREDIT_SCORE >= 700 THEN 'Good (700-749)'
                WHEN CREDIT_SCORE >= 650 THEN 'Fair (650-699)'
                WHEN CREDIT_SCORE >= 600 THEN 'Poor (600-649)'
                ELSE 'Very Poor (<600)'
            END AS CREDIT_TIER
        FROM {GOLD}.CUST360_DIM_CUSTOMER
        WHERE CUSTOMER_SEGMENT IN ('{seg_filter}')
          AND RISK_RATING       IN ('{risk_filter}')
    """
    )

    if not cust_df.empty:
        col1, col2 = st.columns(2)
        with col1:
            fig = px.histogram(
                cust_df,
                x="ANNUAL_INCOME",
                nbins=20,
                color="INCOME_TIER",
                title="Annual Income Distribution",
                labels={"ANNUAL_INCOME": "Annual Income (USD)"},
            )
            st.plotly_chart(fig, use_container_width=True)

        with col2:
            fig = px.histogram(
                cust_df,
                x="CREDIT_SCORE",
                nbins=15,
                color="CREDIT_TIER",
                title="Credit Score Distribution",
                color_discrete_map={
                    "Excellent (750+)": "#2ecc71",
                    "Good (700-749)": "#27ae60",
                    "Fair (650-699)": "#f39c12",
                    "Poor (600-649)": "#e67e22",
                    "Very Poor (<600)": "#e74c3c",
                },
            )
            st.plotly_chart(fig, use_container_width=True)

        col3, col4 = st.columns(2)
        with col3:
            fig = px.pie(
                cust_df["CUSTOMER_SEGMENT"].value_counts().reset_index(),
                names="CUSTOMER_SEGMENT",
                values="count",
                title="Customers by Segment",
                hole=0.4,
            )
            st.plotly_chart(fig, use_container_width=True)

        with col4:
            fig = px.pie(
                cust_df["EMPLOYMENT_STATUS"].value_counts().reset_index(),
                names="EMPLOYMENT_STATUS",
                values="count",
                title="Employment Status Mix",
                hole=0.4,
            )
            st.plotly_chart(fig, use_container_width=True)

        st.subheader("Customer Directory")
        st.dataframe(
            cust_df[
                [
                    "CUSTOMER_ID",
                    "FULL_NAME",
                    "CUSTOMER_SEGMENT",
                    "CUSTOMER_TIER",
                    "ANNUAL_INCOME",
                    "CREDIT_SCORE",
                    "CREDIT_TIER",
                    "RISK_RATING",
                    "KYC_STATUS",
                    "CITY",
                    "STATE",
                    "BRANCH_ID",
                ]
            ].sort_values("ANNUAL_INCOME", ascending=False),
            use_container_width=True,
            height=400,
        )
    else:
        st.info("No customers match the selected filters.")


# ═════════════════════════════════════════════════════════════
# TAB 3 — LOAN PORTFOLIO
# ═════════════════════════════════════════════════════════════
with tab3:
    st.subheader("Loan Portfolio Health")

    loan_df = run_query(
        f"""
        SELECT
            l.LOAN_TYPE,
            l.LOAN_STATUS,
            COUNT(*)                                               AS LOAN_COUNT,
            COALESCE(SUM(l.LOAN_AMOUNT), 0)                        AS TOTAL_LOAN_AMOUNT,
            COALESCE(SUM(l.OUTSTANDING_BALANCE), 0)                AS TOTAL_OUTSTANDING,
            ROUND(AVG(l.INTEREST_RATE), 2)                         AS AVG_INTEREST_RATE,
            COALESCE(ROUND(
                SUM(l.LOAN_AMOUNT - l.OUTSTANDING_BALANCE)
                / NULLIF(SUM(l.LOAN_AMOUNT), 0) * 100, 2), 0)     AS AVG_PAYDOWN_PCT,
            SUM(CASE WHEN l.LOAN_STATUS IN ('Defaulted','Delinquent')
                THEN 1 ELSE 0 END)                                 AS AT_RISK_COUNT
        FROM {GOLD}.CUST360_FACT_LOANS l
        JOIN {GOLD}.CUST360_DIM_CUSTOMER c ON l.CUSTOMER_ID = c.CUSTOMER_ID
        WHERE c.CUSTOMER_SEGMENT IN ('{seg_filter}')
        GROUP BY 1, 2
        ORDER BY 1, 2
    """
    )

    if not loan_df.empty:
        col1, col2, col3 = st.columns(3)
        col1.metric("Total Loans", f"{safe_int(loan_df['LOAN_COUNT'].sum()):,}")
        col2.metric(
            "Total Disbursed", f"${safe_num(loan_df['TOTAL_LOAN_AMOUNT'].sum()):,.0f}"
        )
        col3.metric("At-Risk Loans", f"{safe_int(loan_df['AT_RISK_COUNT'].sum()):,}")
        st.divider()

        col_a, col_b = st.columns(2)
        with col_a:
            by_type = (
                loan_df.groupby("LOAN_TYPE")
                .agg(
                    TOTAL_LOAN_AMOUNT=("TOTAL_LOAN_AMOUNT", "sum"),
                    LOAN_COUNT=("LOAN_COUNT", "sum"),
                )
                .reset_index()
            )
            fig = px.bar(
                by_type,
                x="LOAN_TYPE",
                y="TOTAL_LOAN_AMOUNT",
                color="LOAN_TYPE",
                text_auto=".2s",
                title="Total Loan Book by Type",
            )
            fig.update_layout(showlegend=False)
            st.plotly_chart(fig, use_container_width=True)

        with col_b:
            by_status = loan_df.groupby("LOAN_STATUS")["LOAN_COUNT"].sum().reset_index()
            fig = px.pie(
                by_status,
                names="LOAN_STATUS",
                values="LOAN_COUNT",
                title="Loan Status Distribution",
                hole=0.35,
                color="LOAN_STATUS",
                color_discrete_map={
                    "Active": "#2ecc71",
                    "Closed": "#3498db",
                    "Defaulted": "#e74c3c",
                    "Delinquent": "#e67e22",
                    "Restructured": "#9b59b6",
                },
            )
            st.plotly_chart(fig, use_container_width=True)

        loan_detail = run_query(
            f"""
            SELECT
                l.LOAN_TYPE, l.LOAN_STATUS,
                l.LOAN_AMOUNT, l.OUTSTANDING_BALANCE,
                l.INTEREST_RATE, l.MISSED_PAYMENTS,
                l.LOAN_AMOUNT - l.OUTSTANDING_BALANCE  AS AMOUNT_PAID,
                c.CUSTOMER_SEGMENT, c.CREDIT_SCORE,
                CASE WHEN l.LOAN_STATUS IN ('Defaulted','Delinquent')
                    THEN 1 ELSE 0 END                  AS IS_AT_RISK
            FROM {GOLD}.CUST360_FACT_LOANS l
            JOIN {GOLD}.CUST360_DIM_CUSTOMER c ON l.CUSTOMER_ID = c.CUSTOMER_ID
            WHERE c.CUSTOMER_SEGMENT IN ('{seg_filter}')
        """
        )

        if not loan_detail.empty:
            fig = px.scatter(
                loan_detail,
                x="INTEREST_RATE",
                y="LOAN_AMOUNT",
                color="LOAN_STATUS",
                size="OUTSTANDING_BALANCE",
                facet_col="LOAN_TYPE",
                facet_col_wrap=2,
                title="Loan Amount vs Interest Rate (bubble = Outstanding Balance)",
                labels={
                    "INTEREST_RATE": "Rate (%)",
                    "LOAN_AMOUNT": "Loan Amount (USD)",
                },
                size_max=25,
                opacity=0.7,
            )
            st.plotly_chart(fig, use_container_width=True)

            st.subheader("Loan Detail")
            st.dataframe(
                loan_detail.sort_values("LOAN_AMOUNT", ascending=False),
                use_container_width=True,
                height=350,
            )
    else:
        st.info("No loan data for selected filters.")


# ═════════════════════════════════════════════════════════════
# TAB 4 — TRANSACTIONS
# ═════════════════════════════════════════════════════════════
with tab4:
    st.subheader("Transaction Analytics")

    txn_df = run_query(
        f"""
        SELECT
            DATE_TRUNC('month', t.TRANSACTION_DATE)   AS TXN_MONTH,
            YEAR(t.TRANSACTION_DATE)                  AS YEAR,
            MONTH(t.TRANSACTION_DATE)                 AS MONTH_NUM,
            MONTHNAME(t.TRANSACTION_DATE)             AS MONTH_NAME,
            t.TRANSACTION_TYPE,
            t.CHANNEL,
            t.STATUS,
            COUNT(*)                                  AS TXN_COUNT,
            COALESCE(SUM(t.AMOUNT), 0)                AS TOTAL_AMOUNT,
            SUM(CASE WHEN t.STATUS = 'Failed' THEN 1 ELSE 0 END) AS FAILED_COUNT
        FROM {GOLD}.CUST360_FACT_TRANSACTIONS t
        JOIN {GOLD}.CUST360_DIM_CUSTOMER c ON t.CUSTOMER_ID = c.CUSTOMER_ID
        WHERE c.CUSTOMER_SEGMENT IN ('{seg_filter}')
        GROUP BY 1,2,3,4,5,6,7
        ORDER BY 1
    """
    )

    if not txn_df.empty:
        monthly_agg = (
            txn_df.groupby(["YEAR", "MONTH_NUM", "MONTH_NAME"])
            .agg(
                TXN_COUNT=("TXN_COUNT", "sum"),
                TOTAL_AMOUNT=("TOTAL_AMOUNT", "sum"),
            )
            .reset_index()
            .sort_values(["YEAR", "MONTH_NUM"])
        )
        monthly_agg["PERIOD"] = (
            monthly_agg["MONTH_NAME"] + " " + monthly_agg["YEAR"].astype(str)
        )

        fig = go.Figure()
        fig.add_trace(
            go.Bar(
                x=monthly_agg["PERIOD"],
                y=monthly_agg["TOTAL_AMOUNT"],
                name="Volume ($)",
                marker_color="#3498db",
                opacity=0.7,
                yaxis="y",
            )
        )
        fig.add_trace(
            go.Scatter(
                x=monthly_agg["PERIOD"],
                y=monthly_agg["TXN_COUNT"],
                name="Count",
                mode="lines+markers",
                marker_color="#e74c3c",
                yaxis="y2",
            )
        )
        fig.update_layout(
            title="Monthly Transaction Volume & Count",
            yaxis=dict(title="Total Amount (USD)"),
            yaxis2=dict(title="Count", overlaying="y", side="right"),
            legend=dict(x=0, y=1.1, orientation="h"),
        )
        st.plotly_chart(fig, use_container_width=True)

        col1, col2 = st.columns(2)
        with col1:
            by_type = (
                txn_df.groupby("TRANSACTION_TYPE")["TXN_COUNT"].sum().reset_index()
            )
            fig = px.bar(
                by_type.sort_values("TXN_COUNT", ascending=True),
                x="TXN_COUNT",
                y="TRANSACTION_TYPE",
                orientation="h",
                color="TRANSACTION_TYPE",
                title="Transaction Count by Type",
            )
            fig.update_layout(showlegend=False)
            st.plotly_chart(fig, use_container_width=True)

        with col2:
            by_channel = txn_df.groupby("CHANNEL")["TOTAL_AMOUNT"].sum().reset_index()
            fig = px.pie(
                by_channel,
                names="CHANNEL",
                values="TOTAL_AMOUNT",
                title="Transaction Volume by Channel",
                hole=0.35,
            )
            st.plotly_chart(fig, use_container_width=True)

        failed = (
            txn_df.groupby(["YEAR", "MONTH_NUM", "MONTH_NAME"])["FAILED_COUNT"]
            .sum()
            .reset_index()
        )
        failed = failed.sort_values(["YEAR", "MONTH_NUM"])
        failed["PERIOD"] = failed["MONTH_NAME"] + " " + failed["YEAR"].astype(str)
        fig = px.area(
            failed,
            x="PERIOD",
            y="FAILED_COUNT",
            title="Failed Transactions per Month",
            color_discrete_sequence=["#e74c3c"],
        )
        st.plotly_chart(fig, use_container_width=True)
    else:
        st.info("No transaction data for selected filters.")


# ═════════════════════════════════════════════════════════════
# TAB 5 — RISK & COMPLIANCE
# ═════════════════════════════════════════════════════════════
with tab5:
    st.subheader("Risk & Compliance Overview")

    risk_df = run_query(
        f"""
        SELECT
            c.RISK_RATING,
            c.KYC_STATUS,
            CASE
                WHEN c.CREDIT_SCORE >= 750 THEN 'Excellent (750+)'
                WHEN c.CREDIT_SCORE >= 700 THEN 'Good (700-749)'
                WHEN c.CREDIT_SCORE >= 650 THEN 'Fair (650-699)'
                WHEN c.CREDIT_SCORE >= 600 THEN 'Poor (600-649)'
                ELSE 'Very Poor (<600)'
            END                                                AS CREDIT_TIER,
            COUNT(DISTINCT c.CUSTOMER_ID)                      AS CUSTOMER_COUNT,
            ROUND(AVG(c.ANNUAL_INCOME), 2)                     AS AVG_INCOME,
            COUNT(DISTINCT l.LOAN_ID)                          AS LOAN_COUNT,
            COALESCE(SUM(l.OUTSTANDING_BALANCE), 0)            AS TOTAL_EXPOSURE,
            COALESCE(SUM(CASE WHEN l.LOAN_STATUS IN ('Defaulted','Delinquent')
                THEN l.OUTSTANDING_BALANCE ELSE 0 END), 0)     AS AT_RISK_EXPOSURE
        FROM {GOLD}.CUST360_DIM_CUSTOMER c
        LEFT JOIN {GOLD}.CUST360_FACT_LOANS l ON c.CUSTOMER_ID = l.CUSTOMER_ID
        WHERE c.RISK_RATING IN ('{risk_filter}')
        GROUP BY 1, 2, 3
        ORDER BY 1, 2
    """
    )

    if not risk_df.empty:
        col1, col2, col3, col4 = st.columns(4)
        col1.metric(
            "Total Exposure", f"${safe_num(risk_df['TOTAL_EXPOSURE'].sum()):,.0f}"
        )
        col2.metric(
            "At-Risk Exposure", f"${safe_num(risk_df['AT_RISK_EXPOSURE'].sum()):,.0f}"
        )
        flagged = (
            risk_df[risk_df["KYC_STATUS"] == "Flagged"]["CUSTOMER_COUNT"].sum()
            if "Flagged" in risk_df["KYC_STATUS"].values
            else 0
        )
        col3.metric("Flagged KYC", f"{safe_int(flagged):,}")
        high_risk = (
            risk_df[risk_df["RISK_RATING"] == "High"]["CUSTOMER_COUNT"].sum()
            if "High" in risk_df["RISK_RATING"].values
            else 0
        )
        col4.metric("High-Risk Customers", f"{safe_int(high_risk):,}")
        st.divider()

        col_a, col_b = st.columns(2)
        with col_a:
            risk_sum = (
                risk_df.groupby("RISK_RATING")
                .agg(
                    CUSTOMER_COUNT=("CUSTOMER_COUNT", "sum"),
                    TOTAL_EXPOSURE=("TOTAL_EXPOSURE", "sum"),
                    AT_RISK_EXPOSURE=("AT_RISK_EXPOSURE", "sum"),
                )
                .reset_index()
            )
            fig = px.bar(
                risk_sum,
                x="RISK_RATING",
                y="TOTAL_EXPOSURE",
                color="RISK_RATING",
                color_discrete_map={
                    "Low": "#2ecc71",
                    "Medium": "#f39c12",
                    "High": "#e74c3c",
                },
                text_auto=".2s",
                title="Total Exposure by Risk Rating",
            )
            fig.update_layout(showlegend=False)
            st.plotly_chart(fig, use_container_width=True)

        with col_b:
            kyc_df = risk_df.groupby("KYC_STATUS")["CUSTOMER_COUNT"].sum().reset_index()
            fig = px.pie(
                kyc_df,
                names="KYC_STATUS",
                values="CUSTOMER_COUNT",
                title="KYC Status Distribution",
                hole=0.35,
                color="KYC_STATUS",
                color_discrete_map={
                    "Verified": "#2ecc71",
                    "Pending": "#f39c12",
                    "Flagged": "#e74c3c",
                    "Expired": "#95a5a6",
                },
            )
            st.plotly_chart(fig, use_container_width=True)

        heatmap_df = risk_df.pivot_table(
            index="CREDIT_TIER",
            columns="RISK_RATING",
            values="CUSTOMER_COUNT",
            aggfunc="sum",
            fill_value=0,
        ).reset_index()
        fig = px.imshow(
            heatmap_df.set_index("CREDIT_TIER"),
            color_continuous_scale="RdYlGn_r",
            title="Customer Heatmap: Credit Tier × Risk Rating",
            aspect="auto",
            text_auto=True,
        )
        st.plotly_chart(fig, use_container_width=True)

        aml_df = run_query(
            f"""
            SELECT CUSTOMER_ID, AML_RISK_SCORE, RISK_RATING, CUSTOMER_SEGMENT
            FROM {GOLD}.CUST360_DIM_CUSTOMER
            WHERE RISK_RATING IN ('{risk_filter}')
              AND AML_RISK_SCORE IS NOT NULL
        """
        )
        if not aml_df.empty:
            fig = px.histogram(
                aml_df,
                x="AML_RISK_SCORE",
                nbins=20,
                color="RISK_RATING",
                color_discrete_map={
                    "Low": "#2ecc71",
                    "Medium": "#f39c12",
                    "High": "#e74c3c",
                },
                title="AML Risk Score Distribution",
                labels={"AML_RISK_SCORE": "AML Risk Score (0–100)"},
            )
            st.plotly_chart(fig, use_container_width=True)

        st.subheader("At-Risk Exposure Breakdown")
        st.dataframe(
            risk_df.sort_values("AT_RISK_EXPOSURE", ascending=False),
            use_container_width=True,
            height=300,
        )
    else:
        st.info("No risk data for selected filters.")
